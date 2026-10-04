import 'dart:convert';

import 'package:http/http.dart' as http;

class SlackException implements Exception {
  SlackException(this.message);
  final String message;
  @override
  String toString() => message;
}

class SlackChannel {
  const SlackChannel({required this.id, required this.name, required this.isPrivate});
  final String id;
  final String name;
  final bool isPrivate;
}

/// Slack Web API (Bot Token) 최소 클라이언트.
/// https://api.slack.com/methods/chat.postMessage, auth.test, conversations.list
class SlackApi {
  SlackApi({required this.botToken, http.Client? client}) : _client = client ?? http.Client();

  final String botToken;
  final http.Client _client;

  static const _base = 'https://slack.com/api';

  Future<Map<String, dynamic>> _call(
    String method, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    final uri = Uri.parse('$_base/$method').replace(queryParameters: query);
    final headers = {
      'Authorization': 'Bearer $botToken',
      if (body != null) 'content-type': 'application/json; charset=utf-8',
    };
    final res = await (body != null
            ? _client.post(uri, headers: headers, body: jsonEncode(body))
            : _client.post(uri, headers: headers))
        .timeout(const Duration(seconds: 20));
    final text = utf8.decode(res.bodyBytes);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw SlackException('Slack API 오류 (${res.statusCode})');
    }
    final json = (jsonDecode(text) as Map).cast<String, dynamic>();
    if (json['ok'] != true) {
      throw SlackException(_describeError('${json['error']}'));
    }
    return json;
  }

  /// 토큰이 유효한지 확인하고 워크스페이스/봇 이름을 돌려준다.
  Future<({String team, String user})> authTest() async {
    final j = await _call('auth.test');
    return (team: '${j['team'] ?? ''}', user: '${j['user'] ?? ''}');
  }

  /// 채널 선택용 목록 (봇이 초대된 채널 포함, public + private).
  Future<List<SlackChannel>> listChannels() async {
    final out = <SlackChannel>[];
    String? cursor;
    do {
      final j = await _call(
        'conversations.list',
        query: {
          'types': 'public_channel,private_channel',
          'exclude_archived': 'true',
          'limit': '200',
          if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
        },
      );
      for (final c in (j['channels'] as List? ?? const [])) {
        final m = (c as Map).cast<String, dynamic>();
        out.add(
          SlackChannel(
            id: '${m['id']}',
            name: '${m['name']}',
            isPrivate: m['is_private'] == true,
          ),
        );
      }
      cursor = '${j['response_metadata']?['next_cursor'] ?? ''}';
    } while (cursor.isNotEmpty);
    return out;
  }

  /// 채널에 메시지를 보낸다.
  Future<void> postMessage({required String channel, required String text}) async {
    await _call('chat.postMessage', body: {'channel': channel, 'text': text});
  }

  static String _describeError(String code) => switch (code) {
    'invalid_auth' || 'not_authed' || 'token_revoked' => 'Slack 봇 토큰이 유효하지 않습니다.',
    'account_inactive' => 'Slack 봇 토큰이 비활성화되었습니다.',
    'channel_not_found' => 'Slack 채널을 찾을 수 없습니다.',
    'not_in_channel' => '봇이 이 채널에 초대되어 있지 않습니다. 채널에서 "/invite @봇이름"으로 초대해 주세요.',
    'missing_scope' => 'Slack 앱에 필요한 권한(scope)이 없습니다 (chat:write, channels:read 등).',
    _ => 'Slack API 오류: $code',
  };
}
