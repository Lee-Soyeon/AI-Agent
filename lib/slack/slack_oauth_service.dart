import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// 중계 서버(slack_relay/, Cloudflare Worker) 주소. 빌드 시 주입한다:
/// `flutter build ... --dart-define=SLACK_RELAY_URL=https://ai-agent-slack-relay.xxx.workers.dev`
/// 설정하지 않으면 OAuth 연동 버튼이 비활성화되고, "직접 토큰 입력"만 쓸 수 있다.
const _relayUrl = String.fromEnvironment('SLACK_RELAY_URL');

class SlackOAuthException implements Exception {
  SlackOAuthException(this.message);
  final String message;
  @override
  String toString() => message;
}

class SlackOAuthStart {
  const SlackOAuthStart({required this.state, required this.authorizeUrl});
  final String state;
  final String authorizeUrl;
}

class SlackOAuthResult {
  const SlackOAuthResult({required this.botToken, required this.teamName});
  final String botToken;
  final String teamName;
}

/// Client Secret 을 앱이 몰라도 되는 Slack 연동. code→token 교환은 중계 서버(slack_relay/)가 대신한다.
/// ChatGPT 구독 로그인(기기 코드 방식, [lib/openai/chatgpt_auth.dart])과 같은 패턴: 브라우저에서 승인 →
/// 앱은 결과가 나올 때까지 주기적으로 물어본다. 별도 딥링크 설정이 필요 없다.
class SlackOAuthService {
  SlackOAuthService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// 이 빌드에 중계 서버 주소가 설정되어 있는지.
  static bool get isConfigured => _relayUrl.isNotEmpty;

  /// 1단계: state 발급 + 사용자가 열어야 할 Slack 인증 URL.
  Future<SlackOAuthStart> start() async {
    if (!isConfigured) {
      throw SlackOAuthException(
        '이 빌드에는 Slack 연동 서버 주소(SLACK_RELAY_URL)가 설정되어 있지 않습니다. '
        '"직접 토큰 입력"을 사용하세요.',
      );
    }
    final http.Response res;
    try {
      res = await _client.get(Uri.parse('$_relayUrl/slack/oauth/start')).timeout(const Duration(seconds: 15));
    } catch (e) {
      throw SlackOAuthException('Slack 연동 서버에 연결할 수 없습니다: $e');
    }
    if (res.statusCode != 200) {
      throw SlackOAuthException('Slack 연동 시작 실패 (${res.statusCode})');
    }
    final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    return SlackOAuthStart(state: j['state'] as String, authorizeUrl: j['authorizeUrl'] as String);
  }

  /// 2단계: 사용자가 브라우저에서 승인할 때까지 기다린다 (기본 최대 10분).
  Future<SlackOAuthResult> waitForResult(
    String state, {
    bool Function()? isCancelled,
    Duration timeout = const Duration(minutes: 10),
    Duration interval = const Duration(seconds: 2),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (true) {
      if (isCancelled?.call() ?? false) throw SlackOAuthException('Slack 연동을 취소했습니다.');
      if (DateTime.now().isAfter(deadline)) {
        throw SlackOAuthException('연동 시간이 지났습니다. 다시 시도하세요.');
      }
      final res = await _client
          .get(Uri.parse('$_relayUrl/slack/oauth/result').replace(queryParameters: {'state': state}))
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 202) {
        await Future<void>.delayed(interval);
        continue;
      }
      final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      if (res.statusCode == 404 || j['status'] == 'unknown') {
        throw SlackOAuthException('연동 요청을 찾을 수 없거나 만료되었습니다. 다시 시도하세요.');
      }
      switch (j['status']) {
        case 'done':
          return SlackOAuthResult(
            botToken: j['botToken'] as String,
            teamName: j['teamName'] as String? ?? '',
          );
        case 'denied':
          throw SlackOAuthException('Slack 연동을 거부했습니다.');
        default:
          throw SlackOAuthException('Slack 연동 실패: ${j['message'] ?? j['status']}');
      }
    }
  }
}
