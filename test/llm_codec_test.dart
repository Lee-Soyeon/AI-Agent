import 'package:ai_agent/llm/anthropic_provider.dart';
import 'package:ai_agent/llm/chatgpt_codex_provider.dart';
import 'package:ai_agent/llm/gemini_provider.dart';
import 'package:ai_agent/llm/llm_types.dart';
import 'package:ai_agent/llm/openai_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _tools = [
  ToolSpec(
    name: 'click',
    description: 'click',
    parameters: {
      'type': 'object',
      'properties': {
        'element_id': {'type': 'integer'},
      },
    },
  ),
];

final _history = [
  ChatMessage.user('장바구니 보여줘'),
  ChatMessage.assistant(
    text: '열어볼게요',
    toolCalls: const [
      ToolCall(id: 'c1', name: 'click', arguments: {'element_id': 3}),
      ToolCall(id: 'c2', name: 'click', arguments: {'element_id': 4}),
    ],
  ),
  ChatMessage.toolResult(toolCallId: 'c1', toolName: 'click', content: 'ok1'),
  ChatMessage.toolResult(toolCallId: 'c2', toolName: 'click', content: 'ok2'),
  ChatMessage.user('계속'),
];

void main() {
  test('OpenAI: tool_calls 와 tool 메시지를 올바르게 만든다', () {
    final body = OpenAiProvider.buildBody(
      model: 'm',
      system: 'sys',
      messages: _history,
      tools: _tools,
    );
    final msgs = body['messages'] as List;
    expect(msgs.first, {'role': 'system', 'content': 'sys'});
    expect((msgs[2]['tool_calls'] as List).length, 2);
    expect(msgs[2]['tool_calls'][0]['function']['arguments'], '{"element_id":3}');
    expect(msgs[3], {'role': 'tool', 'tool_call_id': 'c1', 'content': 'ok1'});
    expect(msgs.last['role'], 'user');

    final res = OpenAiProvider.parseResponse({
      'choices': [
        {
          'message': {
            'content': null,
            'tool_calls': [
              {
                'id': 'x',
                'type': 'function',
                'function': {'name': 'click', 'arguments': '{"element_id": 7}'},
              },
            ],
          },
        },
      ],
    });
    expect(res.toolCalls.single.arguments['element_id'], 7);
  });

  test('Anthropic: 연속 tool_result 는 하나의 user 메시지로 묶이고 뒤 user 텍스트도 합쳐진다', () {
    final body = AnthropicProvider.buildBody(
      model: 'm',
      maxTokens: 10,
      system: 'sys',
      messages: _history,
      tools: _tools,
    );
    final msgs = body['messages'] as List;
    expect(msgs.length, 3);
    expect(msgs[1]['role'], 'assistant');
    expect((msgs[1]['content'] as List).where((b) => b['type'] == 'tool_use').length, 2);
    final last = msgs[2]['content'] as List;
    expect(last.map((b) => b['type']).toList(), ['tool_result', 'tool_result', 'text']);
    expect(body['tools'][0]['input_schema'], isNotNull);

    final res = AnthropicProvider.parseResponse({
      'content': [
        {'type': 'text', 'text': '클릭합니다'},
        {
          'type': 'tool_use',
          'id': 't1',
          'name': 'click',
          'input': {'element_id': 2},
        },
      ],
    });
    expect(res.text, '클릭합니다');
    expect(res.toolCalls.single.id, 't1');
    // 원본 블록을 그대로 되돌려 보낸다.
    final echoed = AnthropicProvider.buildBody(
      model: 'm',
      maxTokens: 10,
      system: 's',
      messages: [ChatMessage.user('a'), res.toMessage()],
      tools: _tools,
    );
    expect((echoed['messages'] as List)[1]['content'], res.providerRaw);
  });

  test('Gemini: functionResponse 를 묶고 functionCall 을 파싱한다', () {
    final body = GeminiProvider.buildBody(system: 'sys', messages: _history, tools: _tools);
    final contents = body['contents'] as List;
    expect(contents.length, 3);
    expect(contents[1]['role'], 'model');
    final parts = contents[2]['parts'] as List;
    expect(parts[0]['functionResponse']['name'], 'click');
    expect(parts[1]['functionResponse']['response'], {'result': 'ok2'});
    expect(parts[2], {'text': '계속'});

    final res = GeminiProvider.parseResponse({
      'candidates': [
        {
          'content': {
            'role': 'model',
            'parts': [
              {'text': '생각', 'thought': true},
              {
                'functionCall': {
                  'name': 'click',
                  'args': {'element_id': 5.0},
                },
                'thoughtSignature': 'sig',
              },
            ],
          },
        },
      ],
    });
    expect(res.text, isNull);
    expect(asInt(res.toolCalls.single.arguments['element_id']), 5);
    expect((res.providerRaw as List).length, 2);
  });

  test('도구가 없으면 모든 공급자가 tools 필드를 생략한다 (빈 배열은 API 오류)', () {
    final msgs = [ChatMessage.user('분석해줘')];
    final o = OpenAiProvider.buildBody(model: 'm', system: 's', messages: msgs, tools: const []);
    expect(o.containsKey('tools'), isFalse);
    expect(o.containsKey('tool_choice'), isFalse);
    final a = AnthropicProvider.buildBody(
      model: 'm',
      maxTokens: 10,
      system: 's',
      messages: msgs,
      tools: const [],
    );
    expect(a.containsKey('tools'), isFalse);
    final g = GeminiProvider.buildBody(system: 's', messages: msgs, tools: const []);
    expect(g.containsKey('tools'), isFalse);
    final c = ChatGptCodexProvider.buildBody(
      model: 'm',
      system: 's',
      messages: msgs,
      tools: const [],
    );
    expect(c.containsKey('tools'), isFalse);
    expect(c.containsKey('parallel_tool_calls'), isFalse);
    expect(c['stream'], isTrue);
  });

  test('Anthropic: 워크스페이스 ID 가 있으면 anthropic-workspace-id 헤더를 보낸다', () async {
    final seen = <Map<String, String>>[];
    final client = MockClient((req) async {
      seen.add(req.headers);
      return http.Response('{"content":[{"type":"text","text":"ok"}]}', 200);
    });
    await AnthropicProvider(
      apiKey: 'k',
      model: 'm',
      client: client,
    ).complete(system: 's', messages: [ChatMessage.user('a')], tools: const []);
    await AnthropicProvider(
      apiKey: 'k',
      model: 'm',
      workspaceId: 'wrkspc_1',
      client: client,
    ).complete(system: 's', messages: [ChatMessage.user('a')], tools: const []);
    expect(seen[0].containsKey('anthropic-workspace-id'), isFalse);
    expect(seen[1]['anthropic-workspace-id'], 'wrkspc_1');
  });
}
