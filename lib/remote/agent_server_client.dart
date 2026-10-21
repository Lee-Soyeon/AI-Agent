import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// AI Agent 서버(server/)의 REST API 클라이언트.
class AgentServerClient {
  AgentServerClient({required String baseUrl, required this.token, http.Client? client})
    : baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), ''),
      _client = client ?? http.Client();

  final String baseUrl;
  final String token;
  final http.Client _client;

  Map<String, String> get _headers => {
    'Authorization': 'Bearer $token',
    'content-type': 'application/json',
  };

  Future<Map<String, dynamic>?> _send(String method, String path, [Object? body]) async {
    final uri = Uri.parse('$baseUrl$path');
    final res = await switch (method) {
      'GET' => _client.get(uri, headers: _headers),
      'DELETE' => _client.delete(uri, headers: _headers),
      _ => _client.post(uri, headers: _headers, body: jsonEncode(body ?? {})),
    }.timeout(const Duration(seconds: 30));
    final text = utf8.decode(res.bodyBytes);
    if (res.statusCode == 401) throw AgentServerException('서버 토큰이 올바르지 않습니다.', 401);
    if (res.statusCode >= 300) {
      String msg = text;
      try {
        msg = '${(jsonDecode(text) as Map)['detail']}';
      } catch (_) {}
      throw AgentServerException(msg, res.statusCode);
    }
    final decoded = text.isEmpty ? null : jsonDecode(text);
    return decoded is Map ? decoded.cast<String, dynamic>() : null;
  }

  Future<List<dynamic>> _getList(String path) async {
    final res = await _client
        .get(Uri.parse('$baseUrl$path'), headers: _headers)
        .timeout(const Duration(seconds: 30));
    if (res.statusCode == 401) throw AgentServerException('서버 토큰이 올바르지 않습니다.', 401);
    if (res.statusCode >= 300) throw AgentServerException('목록을 불러오지 못했습니다.', res.statusCode);
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    return decoded is List ? decoded : const [];
  }

  /// 연결 테스트: 서버가 살아 있고 토큰이 맞는지.
  Future<void> ping() async {
    final res = await _client
        .get(Uri.parse('$baseUrl/health'))
        .timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) throw AgentServerException('서버에 연결할 수 없습니다 (${res.statusCode})');
    await current();
  }

  Future<RemoteTask> createTask(String prompt) async =>
      RemoteTask(await _send('POST', '/tasks', {'prompt': prompt}) ?? const {});

  /// 서버에 남아 있는 작업(대화) 목록, 최근 순. 로그는 들어 있지 않다.
  Future<List<RemoteTask>> listTasks() async => [
    for (final t in await _getList('/tasks')) RemoteTask((t as Map).cast<String, dynamic>()),
  ];

  Future<void> deleteTask(String id) => _send('DELETE', '/tasks/$id');

  Future<RemoteTask?> current() async {
    final j = await _send('GET', '/tasks/current');
    return j == null ? null : RemoteTask(j);
  }

  Future<RemoteTask> task(String id, {int since = 0}) async =>
      RemoteTask(await _send('GET', '/tasks/$id?since=$since') ?? const {});

  Future<void> approve(String id, bool approved, {String? feedback}) =>
      _send('POST', '/tasks/$id/approval', {'approved': approved, 'feedback': feedback});

  /// 결제 넘기기 결과 (approved=false 면 승인 카드에서 거절).
  Future<void> payment(
    String id, {
    required bool approved,
    bool completed = false,
    String? feedback,
  }) => _send('POST', '/tasks/$id/payment', {
    'approved': approved,
    'completed': completed,
    'feedback': feedback,
  });

  Future<void> answer(String id, String text) => _send('POST', '/tasks/$id/answer', {'text': text});

  Future<void> helpDone(String id) => _send('POST', '/tasks/$id/help_done');

  Future<RemoteTask> followUp(String id, String prompt) async =>
      RemoteTask(await _send('POST', '/tasks/$id/followup', {'prompt': prompt}) ?? const {});

  Future<void> cancel(String id) => _send('POST', '/tasks/$id/cancel');

  Future<void> openUrl(String url) => _send('POST', '/browser/open', {'url': url});

  Future<Uint8List?> screenshot(String id) async {
    final res = await _client.get(Uri.parse('$baseUrl/tasks/$id/screenshot'), headers: _headers);
    return res.statusCode == 200 ? res.bodyBytes : null;
  }

  /// 실시간 서버 브라우저 화면 WebSocket 주소.
  Uri get liveUri {
    final u = Uri.parse(baseUrl);
    return u.replace(
      scheme: u.scheme == 'https' ? 'wss' : 'ws',
      path: '${u.path}/live',
      queryParameters: {'token': token},
    );
  }
}

/// 서버의 작업 상태 (GET /tasks/{id}).
class RemoteTask {
  RemoteTask(this.json);

  final Map<String, dynamic> json;

  String get id => json['id'] as String;
  String get prompt => json['prompt'] as String? ?? '';
  String get status => json['status'] as String? ?? 'running';
  bool get isBusy => const {'running', 'waiting_approval', 'waiting_user'}.contains(status);
  List<Map<String, dynamic>> get logs => [
    for (final l in (json['logs'] as List? ?? const [])) (l as Map).cast<String, dynamic>(),
  ];
  int get logCount => json['log_count'] as int? ?? 0;
  Map<String, dynamic>? get pending => (json['pending'] as Map?)?.cast<String, dynamic>();
  String? get result => json['result'] as String?;
  int get screenshotVersion => json['screenshot_version'] as int? ?? 0;
}

class AgentServerException implements Exception {
  AgentServerException(this.message, [this.statusCode]);
  final String message;
  final int? statusCode;
  @override
  String toString() => message;
}
