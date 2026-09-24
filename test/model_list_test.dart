import 'dart:convert';

import 'package:ai_agent/core/settings_store.dart';
import 'package:ai_agent/llm/llm_types.dart';
import 'package:ai_agent/llm/model_list.dart';
import 'package:ai_agent/llm/openai_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response json(Object body, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status);

void main() {
  test('Gemini: generateContent 를 지원하는 모델만, 여러 페이지를 모아서', () async {
    final seen = <Uri>[];
    final lister = ModelLister(
      client: MockClient((req) async {
        seen.add(req.url);
        expect(req.headers['x-goog-api-key'], 'k');
        return req.url.queryParameters['pageToken'] == null
            ? json({
                'models': [
                  {
                    'name': 'models/gemini-3.6-flash',
                    'supportedGenerationMethods': ['generateContent'],
                  },
                  {
                    'name': 'models/text-embedding-005',
                    'supportedGenerationMethods': ['embedContent'],
                  },
                ],
                'nextPageToken': 'p2',
              })
            : json({
                'models': [
                  {
                    'name': 'models/gemini-3.1-flash-lite',
                    'supportedGenerationMethods': ['generateContent'],
                  },
                ],
              });
      }),
    );
    expect(await lister.gemini('k'), ['gemini-3.6-flash', 'gemini-3.1-flash-lite']);
    expect(seen, hasLength(2));
  });

  test('OpenAI·Grok: 대화 모델만, 공급자별 주소', () async {
    final urls = <String>[];
    final lister = ModelLister(
      client: MockClient((req) async {
        urls.add(req.url.toString());
        return json({
          'data': [
            {'id': 'grok-4.3'},
            {'id': 'grok-imagine-image'},
            {'id': 'text-embedding-3-small'},
            {'id': 'grok-4.7'},
          ],
        });
      }),
    );
    expect(await lister.grok('k'), ['grok-4.7', 'grok-4.3']);
    await lister.openai('k');
    expect(urls, ['https://api.x.ai/v1/models', 'https://api.openai.com/v1/models']);
  });

  test('OpenRouter: 도구 호출 되는 모델만, 무료가 위로', () async {
    final lister = ModelLister(
      client: MockClient(
        (req) async => json({
          'data': [
            {
              'id': 'openai/gpt-5.5',
              'supported_parameters': ['tools', 'temperature'],
            },
            {
              'id': 'meta/llama-4:free',
              'supported_parameters': ['tools'],
            },
            {
              'id': 'some/no-tools:free',
              'supported_parameters': ['temperature'],
            },
          ],
        }),
      ),
    );
    expect(await lister.openRouter(''), ['openrouter/free', 'meta/llama-4:free', 'openai/gpt-5.5']);
  });

  test('목록 조회 실패 시 공급자 메시지를 그대로 보여준다', () async {
    final lister = ModelLister(
      client: MockClient(
        (req) async => json({
          'error': {'message': 'API key not valid'},
        }, 400),
      ),
    );
    await expectLater(
      lister.gemini('bad'),
      throwsA(isA<LlmException>().having((e) => e.message, 'message', 'API key not valid')),
    );
  });

  test('Grok·OpenRouter 는 OpenAI 형식으로 각자 주소에 요청한다', () async {
    final seen = <http.Request>[];
    final client = MockClient((req) async {
      seen.add(req);
      return json({
        'choices': [
          {
            'message': {'content': 'ok'},
          },
        ],
      });
    });
    for (final p in [
      OpenAiProvider.grok(apiKey: 'xk', model: LlmVendor.grok.defaultModel, client: client),
      OpenAiProvider.openRouter(
        apiKey: 'ok',
        model: LlmVendor.openrouter.defaultModel,
        client: client,
      ),
    ]) {
      final r = await p.complete(system: 's', messages: [ChatMessage.user('hi')], tools: const []);
      expect(r.text, 'ok');
    }
    expect(seen[0].url.toString(), 'https://api.x.ai/v1/chat/completions');
    expect(seen[0].headers['authorization'], 'Bearer xk');
    expect(jsonDecode(seen[0].body)['model'], 'grok-4.3');
    expect(seen[1].url.toString(), 'https://openrouter.ai/api/v1/chat/completions');
    expect(seen[1].headers['X-Title'], 'AI Agent');
    expect(jsonDecode(seen[1].body)['model'], 'openrouter/free');
  });
}
