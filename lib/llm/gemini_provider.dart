import 'package:http/http.dart' as http;

import 'http_util.dart';
import 'llm_types.dart';

/// Google Gemini generateContent API (function calling).
class GeminiProvider implements LlmProvider {
  GeminiProvider({required this.apiKey, required this.model, http.Client? client})
    : _client = client ?? http.Client();

  final String apiKey;
  final String model;
  final http.Client _client;

  @override
  String get displayName => 'Gemini · $model';

  static Map<String, dynamic> buildBody({
    required String system,
    required List<ChatMessage> messages,
    required List<ToolSpec> tools,
  }) {
    final contents = <Map<String, dynamic>>[];
    for (final m in messages) {
      switch (m.role) {
        case ChatRole.user:
          final part = <String, dynamic>{'text': m.text ?? ''};
          if (contents.isNotEmpty && contents.last['role'] == 'user') {
            (contents.last['parts'] as List).add(part);
          } else {
            contents.add({
              'role': 'user',
              'parts': <dynamic>[part],
            });
          }
        case ChatRole.assistant:
          final raw = m.providerRaw;
          contents.add({
            'role': 'model',
            // thoughtSignature 등을 보존하기 위해 원본 parts 를 그대로 되돌려 보낸다.
            'parts': raw is List
                ? raw
                : [
                    if ((m.text ?? '').isNotEmpty) {'text': m.text},
                    for (final c in m.toolCalls)
                      {
                        'functionCall': {'name': c.name, 'args': c.arguments},
                      },
                  ],
          });
        case ChatRole.tool:
          final part = <String, dynamic>{
            'functionResponse': {
              'name': m.toolName,
              'response': {'result': m.text ?? ''},
            },
          };
          final last = contents.isEmpty ? null : contents.last;
          if (last != null &&
              last['role'] == 'user' &&
              (last['parts'] as List).every((p) => (p as Map).containsKey('functionResponse'))) {
            (last['parts'] as List).add(part);
          } else {
            contents.add({
              'role': 'user',
              'parts': <dynamic>[part],
            });
          }
      }
    }
    return {
      'systemInstruction': {
        'parts': [
          {'text': system},
        ],
      },
      'contents': contents,
      if (tools.isNotEmpty)
        'tools': [
          {
            'functionDeclarations': [
              for (final t in tools)
                {'name': t.name, 'description': t.description, 'parameters': t.parameters},
            ],
          },
        ],
    };
  }

  static LlmResponse parseResponse(Map<String, dynamic> json) {
    final candidates = json['candidates'] as List? ?? const [];
    if (candidates.isEmpty) {
      final reason = (json['promptFeedback'] as Map?)?['blockReason'];
      throw LlmException('Gemini 응답이 비어 있습니다${reason == null ? '' : ' ($reason)'}.');
    }
    final content = (candidates.first as Map)['content'] as Map? ?? const {};
    final parts = (content['parts'] as List? ?? const []).cast<Map>();
    final texts = <String>[];
    final calls = <ToolCall>[];
    var i = 0;
    for (final p in parts) {
      if (p['thought'] == true) continue;
      if (p['text'] is String) texts.add(p['text'] as String);
      final fc = p['functionCall'];
      if (fc is Map) {
        calls.add(
          ToolCall(
            id:
                fc['id'] as String? ??
                'gemini_call_${DateTime.now().microsecondsSinceEpoch}_${i++}',
            name: fc['name'] as String,
            arguments: decodeArgs(fc['args']),
          ),
        );
      }
    }
    return LlmResponse(
      text: texts.isEmpty ? null : texts.join('\n'),
      toolCalls: calls,
      providerRaw: parts,
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
      Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent'),
      headers: {'x-goog-api-key': apiKey},
      body: buildBody(system: system, messages: messages, tools: tools),
    );
    return parseResponse(json);
  }
}
