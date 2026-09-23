import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../openai/chatgpt_auth.dart';
import 'http_util.dart';
import 'llm_types.dart';

/// ChatGPT 구독 로그인으로 Codex 백엔드(Responses API 형식)를 호출한다.
///
/// - 요청은 스트리밍(SSE)만 지원되고 `store: false` 여야 한다.
/// - OpenAI 는 외부 앱이 스스로를 밝히도록 요구하므로 Codex CLI 로 위장하지 않고
///   앱 고유의 `originator` / `User-Agent` 를 보낸다.
class ChatGptCodexProvider implements LlmProvider {
  ChatGptCodexProvider({
    required this.auth,
    required this.model,
    this.baseUrl = 'https://chatgpt.com/backend-api/codex',
    http.Client? client,
  }) : _client = client ?? http.Client();

  static const originator = 'ai_agent_flutter';
  static const userAgent = 'AIAgentFlutter/1.0';

  final ChatGptAuth auth;
  final String model;
  final String baseUrl;
  final http.Client _client;

  @override
  String get displayName => 'ChatGPT 구독 · $model';

  static Map<String, dynamic> buildBody({
    required String model,
    required String system,
    required List<ChatMessage> messages,
    required List<ToolSpec> tools,
  }) {
    final input = <Map<String, dynamic>>[];
    for (final m in messages) {
      switch (m.role) {
        case ChatRole.user:
          input.add({
            'type': 'message',
            'role': 'user',
            'content': [
              {'type': 'input_text', 'text': m.text ?? ''},
            ],
          });
        case ChatRole.assistant:
          if ((m.text ?? '').isNotEmpty) {
            input.add({
              'type': 'message',
              'role': 'assistant',
              'content': [
                {'type': 'output_text', 'text': m.text},
              ],
            });
          }
          for (final c in m.toolCalls) {
            input.add({
              'type': 'function_call',
              'call_id': c.id,
              'name': c.name,
              'arguments': jsonEncode(c.arguments),
            });
          }
        case ChatRole.tool:
          input.add({
            'type': 'function_call_output',
            'call_id': m.toolCallId,
            'output': m.text ?? '',
          });
      }
    }
    return {
      'model': model,
      'instructions': system,
      'input': input,
      'tools': [
        for (final t in tools)
          {
            'type': 'function',
            'name': t.name,
            'description': t.description,
            'parameters': t.parameters,
            'strict': false,
          },
      ],
      'tool_choice': 'auto',
      'parallel_tool_calls': true,
      'store': false,
      'stream': true,
    };
  }

  /// SSE 스트림을 읽어 완성된 output 항목들로 응답을 만든다.
  static LlmResponse parseSse(String body) {
    final done = <Map<String, dynamic>>[];
    List? completedOutput;
    for (final line in const LineSplitter().convert(body)) {
      if (!line.startsWith('data:')) continue;
      final data = line.substring(5).trim();
      if (data.isEmpty || data == '[DONE]') continue;
      final Map<String, dynamic> ev;
      try {
        ev = jsonDecode(data) as Map<String, dynamic>;
      } catch (_) {
        continue;
      }
      switch (ev['type']) {
        case 'response.output_item.done':
          done.add((ev['item'] as Map).cast<String, dynamic>());
        case 'response.completed':
          completedOutput = (ev['response'] as Map?)?['output'] as List?;
        case 'response.failed':
        case 'error':
          final err = ((ev['response'] as Map?)?['error'] ?? ev['error'] ?? ev) as Map;
          throw LlmException('ChatGPT 응답 실패: ${err['message'] ?? err['code'] ?? ev}');
        case 'response.incomplete':
          final reason = ((ev['response'] as Map?)?['incomplete_details'] as Map?)?['reason'];
          throw LlmException('ChatGPT 응답이 중간에 끊겼습니다 (${reason ?? 'unknown'}).');
      }
    }
    // 일부 응답은 output_item.done 없이 completed 에만 결과가 담긴다.
    final items = done.isNotEmpty
        ? done
        : [for (final i in completedOutput ?? const []) (i as Map).cast<String, dynamic>()];
    return parseOutput(items);
  }

  static LlmResponse parseOutput(List<Map<String, dynamic>> items) {
    final texts = <String>[];
    final calls = <ToolCall>[];
    for (final item in items) {
      switch (item['type']) {
        case 'message':
          for (final c in (item['content'] as List? ?? const [])) {
            if ((c as Map)['type'] == 'output_text') texts.add(c['text'] as String? ?? '');
          }
        case 'function_call':
          calls.add(
            ToolCall(
              id: (item['call_id'] ?? item['id']) as String,
              name: item['name'] as String,
              arguments: decodeArgs(item['arguments']),
            ),
          );
      }
    }
    return LlmResponse(text: texts.isEmpty ? null : texts.join('\n'), toolCalls: calls);
  }

  @override
  Future<LlmResponse> complete({
    required String system,
    required List<ChatMessage> messages,
    required List<ToolSpec> tools,
  }) async {
    final body = jsonEncode(
      buildBody(model: model, system: system, messages: messages, tools: tools),
    );

    Future<http.Response> send({bool refresh = false}) async {
      final Map<String, String> authHeaders;
      try {
        authHeaders = await auth.authHeaders(forceRefresh: refresh);
      } on ChatGptAuthException catch (e) {
        throw LlmException(e.message, statusCode: 401);
      }
      return _client
          .post(
            Uri.parse('$baseUrl/responses'),
            headers: {
              ...authHeaders,
              'content-type': 'application/json',
              'accept': 'text/event-stream',
              'originator': originator,
              'User-Agent': userAgent,
            },
            body: body,
          )
          .timeout(const Duration(seconds: 180));
    }

    var res = await send();
    if (res.statusCode == 401) res = await send(refresh: true);
    final text = utf8.decode(res.bodyBytes, allowMalformed: true);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw LlmException(_describeError(res.statusCode, text), statusCode: res.statusCode);
    }
    return parseSse(text);
  }

  static String _describeError(int status, String body) {
    String detail = body.length > 300 ? '${body.substring(0, 300)}…' : body;
    try {
      final j = jsonDecode(body) as Map;
      final e = (j['error'] ?? j['detail'] ?? j) as Object;
      detail = e is Map ? '${e['message'] ?? e['code'] ?? e}' : '$e';
    } catch (_) {}
    return switch (status) {
      401 || 403 => 'ChatGPT 인증 실패 — 설정에서 다시 로그인하세요. ($detail)',
      404 => '이 모델을 ChatGPT 구독으로 쓸 수 없습니다. 설정에서 모델을 바꿔 보세요. ($detail)',
      429 => 'ChatGPT 요금제 사용 한도에 도달했거나 요청이 너무 많습니다. ($detail)',
      _ => detail,
    };
  }
}
