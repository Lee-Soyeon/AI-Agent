import 'dart:convert';

import 'package:http/http.dart' as http;

import 'llm_types.dart';

Future<Map<String, dynamic>> postJson(
  http.Client client,
  Uri uri, {
  required Map<String, String> headers,
  required Map<String, dynamic> body,
  Duration timeout = const Duration(seconds: 120),
}) async {
  final res = await client
      .post(uri, headers: {'content-type': 'application/json', ...headers}, body: jsonEncode(body))
      .timeout(timeout);
  final text = utf8.decode(res.bodyBytes);
  if (res.statusCode < 200 || res.statusCode >= 300) {
    throw LlmException(_errorMessage(text), statusCode: res.statusCode);
  }
  final decoded = jsonDecode(text);
  if (decoded is! Map<String, dynamic>) {
    throw LlmException('예상하지 못한 응답 형식: $text');
  }
  return decoded;
}

String _errorMessage(String body) {
  try {
    final j = jsonDecode(body);
    if (j is Map && j['error'] is Map) {
      return (j['error'] as Map)['message']?.toString() ?? body;
    }
  } catch (_) {}
  return body.length > 500 ? '${body.substring(0, 500)}…' : body;
}

Map<String, dynamic> decodeArgs(Object? raw) {
  if (raw is Map<String, dynamic>) return raw;
  if (raw is Map) return raw.map((k, v) => MapEntry(k.toString(), v));
  if (raw is String && raw.trim().isNotEmpty) {
    try {
      final j = jsonDecode(raw);
      if (j is Map) return j.map((k, v) => MapEntry(k.toString(), v));
    } catch (_) {}
  }
  return <String, dynamic>{};
}
