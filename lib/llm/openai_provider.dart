import 'dart:convert';

import 'package:http/http.dart' as http;

import 'http_util.dart';
import 'llm_types.dart';

/// OpenAI Chat Completions API (function calling).
/// 같은 형식을 쓰는 xAI(Grok)·OpenRouter 도 [baseUrl] 만 바꿔 그대로 쓴다.
class OpenAiProvider implements LlmProvider {
  OpenAiProvider({
    required this.apiKey,
    required this.model,
    this.baseUrl = 'https://api.openai.com/v1',
    this.name = 'OpenAI',
    this.extraHeaders = const {},
    http.Client? client,
  }) : _client = client ?? http.Client();

  factory OpenAiProvider.grok({
    required String apiKey,
    required String model,
    http.Client? client,
  }) => OpenAiProvider(
    apiKey: apiKey,
    model: model,
    baseUrl: 'https://api.x.ai/v1',
    name: 'Grok',
    client: client,
  );

  factory OpenAiProvider.openRouter({
    required String apiKey,
    required String model,
    http.Client? client,
  }) => OpenAiProvider(
    apiKey: apiKey,
    model: model,
    baseUrl: 'https://openrouter.ai/api/v1',
    name: 'OpenRouter',
    // OpenRouter 대시보드에 앱 이름으로 표시된다 (선택 헤더)
    extraHeaders: const {'X-Title': 'AI Agent'},
    client: client,
  );

  final String apiKey;
  final String model;
  final String baseUrl;
  final String name;
  final Map<String, String> extraHeaders;
  final http.Client _client;

  @override
  String get displayName => '$name · $model';

  static Map<String, dynamic> buildBody({
    required String model,
    required String system,
    required List<ChatMessage> messages,
    required List<ToolSpec> tools,
  }) {
    final out = <Map<String, dynamic>>[
      {'role': 'system', 'content': system},
    ];
    for (final m in messages) {
      switch (m.role) {
        case ChatRole.user:
          out.add({'role': 'user', 'content': m.text ?? ''});
        case ChatRole.assistant:
          out.add({
            'role': 'assistant',
            'content': m.text,
            if (m.toolCalls.isNotEmpty)
              'tool_calls': [
                for (final c in m.toolCalls)
                  {
                    'id': c.id,
                    'type': 'function',
                    'function': {'name': c.name, 'arguments': jsonEncode(c.arguments)},
                  },
              ],
          });
        case ChatRole.tool:
          out.add({'role': 'tool', 'tool_call_id': m.toolCallId, 'content': m.text ?? ''});
      }
    }
    return {
      'model': model,
      'messages': out,
      // 빈 tools 배열은 API 가 거부하므로 도구가 없으면 필드를 생략한다.
      if (tools.isNotEmpty) ...{
        'tools': [
          for (final t in tools)
            {
              'type': 'function',
              'function': {
                'name': t.name,
                'description': t.description,
                'parameters': t.parameters,
              },
            },
        ],
        'tool_choice': 'auto',
      },
    };
  }

  static LlmResponse parseResponse(Map<String, dynamic> json) {
    final choices = json['choices'] as List? ?? const [];
    if (choices.isEmpty) throw LlmException('OpenAI 응답에 choices 가 없습니다.');
    final msg = (choices.first as Map)['message'] as Map? ?? const {};
    final calls = <ToolCall>[
      for (final c in (msg['tool_calls'] as List? ?? const []))
        ToolCall(
          id: (c as Map)['id'] as String,
          name: (c['function'] as Map)['name'] as String,
          arguments: decodeArgs((c['function'] as Map)['arguments']),
        ),
    ];
    return LlmResponse(text: msg['content'] as String?, toolCalls: calls);
  }

  @override
  Future<LlmResponse> complete({
    required String system,
    required List<ChatMessage> messages,
    required List<ToolSpec> tools,
  }) async {
    final json = await postJson(
      _client,
      Uri.parse('$baseUrl/chat/completions'),
      headers: {'authorization': 'Bearer $apiKey', ...extraHeaders},
      body: buildBody(model: model, system: system, messages: messages, tools: tools),
    );
    return parseResponse(json);
  }
}
