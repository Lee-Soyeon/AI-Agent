/// 공급자(OpenAI / Anthropic / Gemini)와 무관한 공통 메시지·도구 타입.
library;

/// LLM 에게 노출되는 도구 정의. [parameters] 는 JSON Schema(object) 이다.
class ToolSpec {
  const ToolSpec({required this.name, required this.description, required this.parameters});

  final String name;
  final String description;
  final Map<String, dynamic> parameters;
}

/// LLM 이 요청한 도구 호출.
class ToolCall {
  const ToolCall({required this.id, required this.name, required this.arguments});

  final String id;
  final String name;
  final Map<String, dynamic> arguments;
}

enum ChatRole { user, assistant, tool }

class ChatMessage {
  const ChatMessage._({
    required this.role,
    this.text,
    this.toolCalls = const [],
    this.toolCallId,
    this.toolName,
    this.providerRaw,
  });

  factory ChatMessage.user(String text) => ChatMessage._(role: ChatRole.user, text: text);

  /// [providerRaw] 는 공급자 원본 응답(예: Gemini thoughtSignature, Claude thinking 블록)을
  /// 다음 요청에 그대로 되돌려 보내기 위해 보관한다.
  factory ChatMessage.assistant({
    String? text,
    List<ToolCall> toolCalls = const [],
    Object? providerRaw,
  }) => ChatMessage._(
    role: ChatRole.assistant,
    text: text,
    toolCalls: toolCalls,
    providerRaw: providerRaw,
  );

  factory ChatMessage.toolResult({
    required String toolCallId,
    required String toolName,
    required String content,
  }) =>
      ChatMessage._(role: ChatRole.tool, text: content, toolCallId: toolCallId, toolName: toolName);

  final ChatRole role;
  final String? text;
  final List<ToolCall> toolCalls;
  final String? toolCallId;
  final String? toolName;
  final Object? providerRaw;

  ChatMessage withText(String newText) => ChatMessage._(
    role: role,
    text: newText,
    toolCalls: toolCalls,
    toolCallId: toolCallId,
    toolName: toolName,
    providerRaw: providerRaw,
  );
}

class LlmResponse {
  const LlmResponse({this.text, this.toolCalls = const [], this.providerRaw});

  final String? text;
  final List<ToolCall> toolCalls;
  final Object? providerRaw;

  ChatMessage toMessage() =>
      ChatMessage.assistant(text: text, toolCalls: toolCalls, providerRaw: providerRaw);
}

class LlmException implements Exception {
  LlmException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() =>
      statusCode == null ? 'LlmException: $message' : 'LlmException($statusCode): $message';
}

abstract class LlmProvider {
  String get displayName;

  Future<LlmResponse> complete({
    required String system,
    required List<ChatMessage> messages,
    required List<ToolSpec> tools,
  });
}

/// 도구 인자가 문자열/실수 등으로 와도 안전하게 정수로 변환한다.
int? asInt(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v.trim());
  return null;
}
