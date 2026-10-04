import 'dart:convert';

import 'package:ai_agent/slack/slack_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('postMessage: 토큰·채널·텍스트를 그대로 보낸다', () async {
    Map<String, dynamic>? sentBody;
    String? authHeader;
    final client = MockClient((req) async {
      authHeader = req.headers['Authorization'];
      sentBody = jsonDecode(req.body) as Map<String, dynamic>;
      expect(req.url.path, '/api/chat.postMessage');
      return http.Response(jsonEncode({'ok': true}), 200);
    });
    final api = SlackApi(botToken: 'xoxb-test', client: client);
    await api.postMessage(channel: 'C123', text: '안녕하세요');
    expect(authHeader, 'Bearer xoxb-test');
    expect(sentBody, {'channel': 'C123', 'text': '안녕하세요'});
  });

  test('authTest: team/user 를 돌려준다', () async {
    final client = MockClient((req) async {
      expect(req.url.path, '/api/auth.test');
      return http.Response(jsonEncode({'ok': true, 'team': '우리회사', 'user': 'ai_agent_bot'}), 200);
    });
    final api = SlackApi(botToken: 'xoxb-test', client: client);
    final auth = await api.authTest();
    expect(auth.team, '우리회사');
    expect(auth.user, 'ai_agent_bot');
  });

  test('listChannels: 페이지네이션을 따라가며 모은다', () async {
    var calls = 0;
    final client = MockClient((req) async {
      calls++;
      if (calls == 1) {
        expect(req.url.queryParameters['cursor'], isNull);
        return http.Response(
          jsonEncode({
            'ok': true,
            'channels': [
              {'id': 'C1', 'name': 'general', 'is_private': false},
            ],
            'response_metadata': {'next_cursor': 'page2'},
          }),
          200,
        );
      }
      expect(req.url.queryParameters['cursor'], 'page2');
      return http.Response(
        jsonEncode({
          'ok': true,
          'channels': [
            {'id': 'C2', 'name': 'work-alerts', 'is_private': true},
          ],
          'response_metadata': {'next_cursor': ''},
        }),
        200,
      );
    });
    final api = SlackApi(botToken: 'xoxb-test', client: client);
    final channels = await api.listChannels();
    expect(channels.map((c) => c.id), ['C1', 'C2']);
    expect(channels.last.isPrivate, isTrue);
    expect(calls, 2);
  });

  test('ok:false 오류를 사람이 읽을 수 있는 메시지로 바꾼다', () async {
    final client = MockClient(
      (req) async => http.Response(jsonEncode({'ok': false, 'error': 'not_in_channel'}), 200),
    );
    final api = SlackApi(botToken: 'xoxb-test', client: client);
    await expectLater(
      api.postMessage(channel: 'C1', text: 'hi'),
      throwsA(isA<SlackException>().having((e) => e.message, 'message', contains('초대'))),
    );
  });
}
