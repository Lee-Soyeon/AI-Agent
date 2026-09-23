import 'dart:convert';

import 'package:ai_agent/llm/chatgpt_codex_provider.dart';
import 'package:ai_agent/llm/llm_types.dart';
import 'package:ai_agent/openai/chatgpt_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

String jwt(Map<String, dynamic> payload) =>
    'h.${base64Url.encode(utf8.encode(jsonEncode(payload))).replaceAll('=', '')}.s';

String accessToken({required int expSeconds, String account = 'acct-1'}) => jwt({
  'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + expSeconds,
  'https://api.openai.com/auth': {'chatgpt_account_id': account},
});

final idToken = jwt({
  'email': 'me@example.com',
  'https://api.openai.com/auth': {'chatgpt_plan_type': 'plus', 'chatgpt_account_id': 'acct-1'},
});

http.Response json(Object body, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status);

void main() {
  test('기기 코드 로그인: 코드 발급 → 대기(403) → 승인 → 토큰 교환 → 저장', () async {
    var polls = 0;
    Map<String, String>? exchangeForm;
    final client = MockClient((req) async {
      switch (req.url.path) {
        case '/api/accounts/deviceauth/usercode':
          expect(jsonDecode(req.body), {'client_id': ChatGptAuth.clientId});
          return json({'device_auth_id': 'dev-1', 'usercode': 'ABCD-1234', 'interval': '0'});
        case '/api/accounts/deviceauth/token':
          expect(jsonDecode(req.body), {'device_auth_id': 'dev-1', 'user_code': 'ABCD-1234'});
          polls++;
          return polls < 3
              ? json({}, 403)
              : json({
                  'authorization_code': 'code-1',
                  'code_challenge': 'c',
                  'code_verifier': 'v-1',
                });
        case '/oauth/token':
          exchangeForm = req.bodyFields;
          return json({
            'id_token': idToken,
            'access_token': accessToken(expSeconds: 3600),
            'refresh_token': 'rt-1',
          });
      }
      return json({}, 500);
    });
    final store = MemoryChatGptTokenStore();
    final auth = ChatGptAuth(client: client, store: store);

    final code = await auth.requestDeviceCode();
    expect(code.userCode, 'ABCD-1234');
    await auth.completeDeviceLogin(code);

    expect(polls, 3);
    expect(exchangeForm, {
      'grant_type': 'authorization_code',
      'client_id': ChatGptAuth.clientId,
      'code': 'code-1',
      'redirect_uri': 'https://auth.openai.com/deviceauth/callback',
      'code_verifier': 'v-1',
    });
    expect(auth.isSignedIn, isTrue);
    expect(auth.email, 'me@example.com');
    expect(auth.planType, 'plus');
    expect(store.value, isNotNull);
    expect((await auth.authHeaders())['ChatGPT-Account-ID'], 'acct-1');

    // 앱 재시작 후 복원
    final restored = ChatGptAuth(client: client, store: store);
    await restored.load();
    expect(restored.email, 'me@example.com');
  });

  test('만료 임박 토큰은 호출 전에 갱신하고, 갱신이 거부되면 로그아웃한다', () async {
    var refreshes = 0;
    var reject = false;
    final client = MockClient((req) async {
      expect(req.url.path, '/oauth/token');
      final body = jsonDecode(req.body) as Map;
      expect(body['grant_type'], 'refresh_token');
      refreshes++;
      if (reject) return json({'error': 'invalid_grant'}, 400);
      return json({'access_token': accessToken(expSeconds: 3600), 'refresh_token': 'rt-2'});
    });
    final store = MemoryChatGptTokenStore()
      ..value = jsonEncode({
        'id_token': idToken,
        'access_token': accessToken(expSeconds: 60), // 5분 이내 만료
        'refresh_token': 'rt-1',
      });
    final auth = ChatGptAuth(client: client, store: store);
    await auth.load();

    // 동시에 두 번 불러도 갱신 요청은 한 번
    await Future.wait([auth.authHeaders(), auth.authHeaders()]);
    expect(refreshes, 1);
    expect(jsonDecode(store.value!)['refresh_token'], 'rt-2');
    expect(auth.email, 'me@example.com'); // 새 응답에 id_token 이 없으면 기존 것 유지

    reject = true;
    await expectLater(auth.authHeaders(forceRefresh: true), throwsA(isA<ChatGptAuthException>()));
    expect(auth.isSignedIn, isFalse);
    expect(store.value, isNull);
  });

  test('Responses 요청 본문: 도구 호출/결과가 call_id 로 이어지고 store=false, stream=true', () {
    final body = ChatGptCodexProvider.buildBody(
      model: 'gpt-5.5',
      system: 'sys',
      messages: [
        ChatMessage.user('안녕'),
        ChatMessage.assistant(
          text: '열게요',
          toolCalls: const [
            ToolCall(id: 'call_1', name: 'open_url', arguments: {'url': 'https://a'}),
          ],
        ),
        ChatMessage.toolResult(toolCallId: 'call_1', toolName: 'open_url', content: 'ok'),
      ],
      tools: const [
        ToolSpec(name: 'open_url', description: 'd', parameters: {'type': 'object'}),
      ],
    );
    expect(body['instructions'], 'sys');
    expect(body['store'], false);
    expect(body['stream'], true);
    final input = body['input'] as List;
    expect(input.map((i) => i['type']).toList(), [
      'message',
      'message',
      'function_call',
      'function_call_output',
    ]);
    expect(input[2]['arguments'], '{"url":"https://a"}');
    expect(input[3]['call_id'], 'call_1');
    expect(body['tools'][0], containsPair('type', 'function'));
  });

  test('실제 호출: 앱 고유 originator 로 보내고, 401 이면 갱신 후 재시도, SSE 를 파싱한다', () async {
    final seen = <Map<String, String>>[];
    var refreshed = false;
    final sse = [
      'event: response.created',
      'data: {"type":"response.created","response":{}}',
      '',
      'data: {"type":"response.output_text.delta","delta":"생"}',
      'data: {"type":"response.output_item.done","item":{"type":"reasoning","summary":[]}}',
      'data: {"type":"response.output_item.done","item":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"검색할게요"}]}}',
      'data: {"type":"response.output_item.done","item":{"type":"function_call","call_id":"call_9","name":"open_url","arguments":"{\\"url\\":\\"https://m.coupang.com\\"}"}}',
      'data: {"type":"response.completed","response":{"output":[]}}',
      '',
    ].join('\n');

    final client = MockClient((req) async {
      if (req.url.host == 'auth.openai.com') {
        refreshed = true;
        return json({'access_token': accessToken(expSeconds: 3600, account: 'acct-2')});
      }
      seen.add(req.headers);
      if (seen.length == 1) return json({'detail': 'expired'}, 401);
      expect(req.url.toString(), 'https://chatgpt.com/backend-api/codex/responses');
      return http.Response.bytes(utf8.encode(sse), 200);
    });
    final auth = ChatGptAuth(
      client: client,
      store: MemoryChatGptTokenStore()
        ..value = jsonEncode({
          'id_token': idToken,
          'access_token': accessToken(expSeconds: 3600),
          'refresh_token': 'rt',
        }),
    );
    await auth.load();
    final provider = ChatGptCodexProvider(auth: auth, model: 'gpt-5.5', client: client);

    final res = await provider.complete(system: 's', messages: [ChatMessage.user('hi')], tools: []);

    expect(refreshed, isTrue);
    expect(seen, hasLength(2));
    expect(seen.last['originator'], 'ai_agent_flutter');
    expect(seen.last['User-Agent'], 'AIAgentFlutter/1.0');
    expect(seen.last['ChatGPT-Account-ID'], 'acct-2');
    expect(res.text, '검색할게요');
    expect(res.toolCalls.single.id, 'call_9');
    expect(res.toolCalls.single.arguments['url'], 'https://m.coupang.com');
  });

  test('SSE: output_item.done 이 없으면 completed.output 사용, 실패 이벤트는 예외', () {
    final r = ChatGptCodexProvider.parseSse(
      'data: {"type":"response.completed","response":{"output":[{"type":"message","content":[{"type":"output_text","text":"끝"}]}]}}\n',
    );
    expect(r.text, '끝');
    expect(
      () => ChatGptCodexProvider.parseSse(
        'data: {"type":"response.failed","response":{"error":{"message":"usage limit"}}}\n',
      ),
      throwsA(isA<LlmException>().having((e) => e.message, 'message', contains('usage limit'))),
    );
  });
}
