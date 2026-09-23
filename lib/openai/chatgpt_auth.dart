import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

/// ChatGPT 구독(Plus/Pro 등) 계정으로 로그인한다.
///
/// OpenClaw · Hermes Agent 와 같은 "ChatGPT 로그인(Codex OAuth)"의 **기기 코드(device code)** 방식을 따른다.
/// 사용자는 Safari 에서 auth.openai.com 에 로그인하고 화면의 코드를 입력한다.
/// 앱은 비밀번호를 보지 않으며 토큰만 기기 보안 저장소(Keychain / Keystore)에 보관한다.
///
/// 주의: 외부 앱용 공식 ChatGPT 로그인이 아직 없어 Codex 의 공개 OAuth 클라이언트를 사용한다.
/// 공개 문서가 없는 방식이라 OpenAI 정책에 따라 바뀌거나 막힐 수 있다.
///
/// 참고 구현: openai/codex `codex-rs/login/src/device_code_auth.rs`, NousResearch/hermes-agent.
class ChatGptAuth extends ChangeNotifier {
  ChatGptAuth({http.Client? client, ChatGptTokenStore? store})
    : _client = client ?? http.Client(),
      _store = store ?? SecureChatGptTokenStore();

  /// Codex 의 공개 OAuth 클라이언트 ID (Codex CLI, OpenClaw, Hermes 가 공통으로 사용).
  static const clientId = 'app_EMoamEEZ73f0CkXaXp7hrann';
  static const issuer = 'https://auth.openai.com';
  static const verificationUrl = '$issuer/codex/device';

  final http.Client _client;
  final ChatGptTokenStore _store;

  ChatGptTokens? _tokens;
  Future<ChatGptTokens>? _refreshing;

  bool get isSignedIn => _tokens != null;
  String? get email => _tokens?.email;
  String? get planType => _tokens?.planType;

  Future<void> load() async {
    try {
      final raw = await _store.read();
      if (raw != null) {
        _tokens = ChatGptTokens.fromTokenResponse(jsonDecode(raw) as Map<String, dynamic>);
      }
    } catch (_) {
      _tokens = null;
    }
    notifyListeners();
  }

  /// 1단계: 사용자에게 보여줄 일회용 코드를 받는다.
  Future<DeviceCode> requestDeviceCode() async {
    final res = await _client.post(
      Uri.parse('$issuer/api/accounts/deviceauth/usercode'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'client_id': clientId}),
    );
    if (res.statusCode == 404) {
      throw ChatGptAuthException('기기 코드 로그인을 사용할 수 없습니다. ChatGPT 보안 설정을 확인하세요.');
    }
    if (res.statusCode != 200) {
      throw ChatGptAuthException('로그인 코드 요청 실패 (${res.statusCode})');
    }
    final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    return DeviceCode(
      deviceAuthId: j['device_auth_id'] as String,
      userCode: (j['user_code'] ?? j['usercode']) as String,
      interval: Duration(seconds: int.tryParse('${j['interval'] ?? 5}'.trim()) ?? 5),
    );
  }

  /// 2단계: 사용자가 브라우저에서 코드를 입력할 때까지 기다린 뒤 토큰을 받는다 (최대 15분).
  Future<void> completeDeviceLogin(
    DeviceCode code, {
    bool Function()? isCancelled,
    Duration timeout = const Duration(minutes: 15),
  }) async {
    final deadline = DateTime.now().add(timeout);
    Map<String, dynamic>? grant;
    while (grant == null) {
      if (isCancelled?.call() ?? false) throw ChatGptAuthException('로그인을 취소했습니다.');
      if (DateTime.now().isAfter(deadline)) {
        throw ChatGptAuthException('로그인 시간(15분)이 지났습니다. 다시 시도하세요.');
      }
      final res = await _client.post(
        Uri.parse('$issuer/api/accounts/deviceauth/token'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'device_auth_id': code.deviceAuthId, 'user_code': code.userCode}),
      );
      if (res.statusCode == 200) {
        grant = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      } else if (res.statusCode == 403 || res.statusCode == 404) {
        await Future<void>.delayed(code.interval); // 아직 사용자가 승인하지 않음
      } else {
        throw ChatGptAuthException('로그인 실패 (${res.statusCode})');
      }
    }

    final res = await _client.post(
      Uri.parse('$issuer/oauth/token'),
      headers: {'content-type': 'application/x-www-form-urlencoded'},
      body: {
        'grant_type': 'authorization_code',
        'client_id': clientId,
        'code': grant['authorization_code'] as String,
        'redirect_uri': '$issuer/deviceauth/callback',
        'code_verifier': grant['code_verifier'] as String,
      },
    );
    if (res.statusCode != 200) throw ChatGptAuthException('토큰 교환 실패 (${res.statusCode})');
    await _save(
      ChatGptTokens.fromTokenResponse(
        jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>,
      ),
    );
  }

  /// Codex 백엔드 호출용 헤더. 만료 5분 전이면 먼저 갱신한다.
  Future<Map<String, String>> authHeaders({bool forceRefresh = false}) async {
    var t = _tokens;
    if (t == null) {
      throw ChatGptAuthException('ChatGPT 계정으로 로그인되어 있지 않습니다. 설정에서 로그인하세요.');
    }
    if (forceRefresh || t.expiresSoon) t = await refresh();
    return {
      'Authorization': 'Bearer ${t.accessToken}',
      if (t.accountId != null) 'ChatGPT-Account-ID': t.accountId!,
    };
  }

  /// 동시에 여러 번 불려도 갱신 요청은 한 번만 보낸다.
  Future<ChatGptTokens> refresh() =>
      _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);

  Future<ChatGptTokens> _doRefresh() async {
    final t = _tokens;
    if (t == null) throw ChatGptAuthException('ChatGPT 계정으로 로그인되어 있지 않습니다.');
    final res = await _client.post(
      Uri.parse('$issuer/oauth/token'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({
        'client_id': clientId,
        'grant_type': 'refresh_token',
        'refresh_token': t.refreshToken,
      }),
    );
    if (res.statusCode == 400 || res.statusCode == 401) {
      await signOut();
      throw ChatGptAuthException('ChatGPT 로그인이 만료되었습니다. 설정에서 다시 로그인하세요.');
    }
    if (res.statusCode != 200) {
      throw ChatGptAuthException('ChatGPT 토큰 갱신 실패 (${res.statusCode})');
    }
    final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final next = ChatGptTokens.fromTokenResponse({
      'id_token': j['id_token'] ?? t.idToken,
      'access_token': j['access_token'],
      'refresh_token': j['refresh_token'] ?? t.refreshToken,
    });
    await _save(next);
    return next;
  }

  Future<void> signOut() async {
    _tokens = null;
    await _store.delete();
    notifyListeners();
  }

  Future<void> _save(ChatGptTokens t) async {
    _tokens = t;
    await _store.write(jsonEncode(t.toJson()));
    notifyListeners();
  }
}

class DeviceCode {
  const DeviceCode({required this.deviceAuthId, required this.userCode, required this.interval});

  final String deviceAuthId;
  final String userCode;
  final Duration interval;
}

class ChatGptTokens {
  ChatGptTokens({
    required this.idToken,
    required this.accessToken,
    required this.refreshToken,
    this.accountId,
    this.email,
    this.planType,
    this.expiresAt,
  });

  factory ChatGptTokens.fromTokenResponse(Map<String, dynamic> j) {
    final id = decodeJwt(j['id_token'] as String? ?? '');
    final access = decodeJwt(j['access_token'] as String);
    final idAuth = (id['https://api.openai.com/auth'] as Map?) ?? const {};
    final accessAuth = (access['https://api.openai.com/auth'] as Map?) ?? const {};
    final profile = (id['https://api.openai.com/profile'] as Map?) ?? const {};
    final exp = access['exp'];
    return ChatGptTokens(
      idToken: j['id_token'] as String? ?? '',
      accessToken: j['access_token'] as String,
      refreshToken: j['refresh_token'] as String,
      // 헤더는 실제로 보내는 access token 과 짝이 맞아야 하므로 access token 의 값을 우선한다.
      accountId: (accessAuth['chatgpt_account_id'] ?? idAuth['chatgpt_account_id']) as String?,
      email: (id['email'] ?? profile['email']) as String?,
      planType: (idAuth['chatgpt_plan_type'] ?? accessAuth['chatgpt_plan_type'])?.toString(),
      expiresAt: exp is num ? DateTime.fromMillisecondsSinceEpoch(exp.toInt() * 1000) : null,
    );
  }

  final String idToken;
  final String accessToken;
  final String refreshToken;
  final String? accountId;
  final String? email;
  final String? planType;
  final DateTime? expiresAt;

  bool get expiresSoon =>
      expiresAt != null && DateTime.now().isAfter(expiresAt!.subtract(const Duration(minutes: 5)));

  Map<String, dynamic> toJson() => {
    'id_token': idToken,
    'access_token': accessToken,
    'refresh_token': refreshToken,
  };
}

/// JWT 의 payload 만 읽는다 (서명 검증은 발급 서버와 직접 통신하므로 생략).
Map<String, dynamic> decodeJwt(String token) {
  final parts = token.split('.');
  if (parts.length < 2) return const {};
  try {
    var p = parts[1].replaceAll('-', '+').replaceAll('_', '/');
    while (p.length % 4 != 0) {
      p += '=';
    }
    final j = jsonDecode(utf8.decode(base64.decode(p)));
    return j is Map<String, dynamic> ? j : const {};
  } catch (_) {
    return const {};
  }
}

class ChatGptAuthException implements Exception {
  ChatGptAuthException(this.message);
  final String message;
  @override
  String toString() => message;
}

abstract class ChatGptTokenStore {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> delete();
}

class SecureChatGptTokenStore implements ChatGptTokenStore {
  static const _key = 'chatgpt_tokens';
  final _secure = const FlutterSecureStorage();

  @override
  Future<String?> read() => _secure.read(key: _key);
  @override
  Future<void> write(String value) => _secure.write(key: _key, value: value);
  @override
  Future<void> delete() => _secure.delete(key: _key);
}

class MemoryChatGptTokenStore implements ChatGptTokenStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String v) async => value = v;
  @override
  Future<void> delete() async => value = null;
}
