import 'package:http/http.dart' as http;

import 'http_util.dart';
import 'llm_types.dart';

/// Anthropic Claude Messages API (tool use).
class AnthropicProvider implements LlmProvider {
  AnthropicProvider({
    required this.apiKey,
    required this.model,
    this.maxTokens = 4096,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String apiKey;
  final String model;
  final int maxTokens;
  final http.Client _client;

  @override
  String get displayName => 'Claude · $model';

  static Map<String, dynamic> buildBody({
    required String model,
    required int maxTokens,
    required String system,
    required List<ChatMessage> messages,
    required List<ToolSpec> tools,
  }) {
    final out = <Map<String, dynamic>>[];
    for (final m in messages) {
      switch (m.role) {
        case ChatRole.user:
          final block = <String, dynamic>{'type': 'text', 'text': m.text ?? ''};
          // finish 도구 결과 뒤에 이어서 지시하는 경우처럼 user 가 연속되면 하나로 합친다.
          if (out.isNotEmpty && out.last['role'] == 'user') {
            (out.last['content'] as List).add(block);
          } else {
            out.add({
              'role': 'user',
              'content': <dynamic>[block],
            });
          }
        case ChatRole.assistant:
          final raw = m.providerRaw;
          out.add({
            'role': 'assistant',
            'content': raw is List
                ? raw
                : [
                    if ((m.text ?? '').isNotEmpty) {'type': 'text', 'text': m.text},
                    for (final c in m.toolCalls)
                      {'type': 'tool_use', 'id': c.id, 'name': c.name, 'input': c.arguments},
                  ],
          });
        case ChatRole.tool:
          final block = <String, dynamic>{
            'type': 'tool_result',
            'tool_use_id': m.toolCallId,
            'content': m.text ?? '',
          };
          // 연속된 tool_result 는 하나의 user 메시지로 묶어야 한다.
          final last = out.isEmpty ? null : out.last;
          if (last != null &&
              last['role'] == 'user' &&
              (last['content'] as List).every((b) => (b as Map)['type'] == 'tool_result')) {
            (last['content'] as List).add(block);
          } else {
            out.add({
              'role': 'user',
              'content': <dynamic>[block],
            });
          }
      }
    }
    return {
      'model': model,
      'max_tokens': maxTokens,
      'system': system,
      'messages': out,
      'tools': [
        for (final t in tools)
          {'name': t.name, 'description': t.description, 'input_schema': t.parameters},
      ],
    };
  }

  static LlmResponse parseResponse(Map<String, dynamic> json) {
    final content = (json['content'] as List? ?? const []).cast<Map>();
    final texts = <String>[];
    final calls = <ToolCall>[];
    for (final b in content) {
      switch (b['type']) {
        case 'text':
          texts.add(b['text'] as String? ?? '');
        case 'tool_use':
          calls.add(
            ToolCall(
              id: b['id'] as String,
              name: b['name'] as String,
              arguments: decodeArgs(b['input']),
            ),
          );
      }
    }
    return LlmResponse(
      text: texts.isEmpty ? null : texts.join('\n'),
      toolCalls: calls,
      providerRaw: content,
    );
  }

  @override
  Future<LlmResponse> complete({
    required String system,
    required List<ChatMessage> messages,
    required List<ToolSpec> tools,
  }) async {
    final json = await postJson(
      _client,
      Uri.parse('https://api.anthropic.com/v1/messages'),
      headers: {'x-api-key': apiKey, 'anthropic-version': '2023-06-01'},
      body: buildBody(
        model: model,
        maxTokens: maxTokens,
        system: system,
        messages: messages,
        tools: tools,
      ),
    );
    return parseResponse(json);
  }
}
