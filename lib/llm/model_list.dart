import 'dart:convert';

import 'package:http/http.dart' as http;

import 'llm_types.dart';

/// 공급자에게 "이 키로 쓸 수 있는 모델"을 물어본다. 모델 이름을 추측하지 않고 목록에서 고르게 하기 위함.
class ModelLister {
  ModelLister({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<Map<String, dynamic>> _get(Uri uri, Map<String, String> headers) async {
    final res = await _client.get(uri, headers: headers).timeout(const Duration(seconds: 20));
    final text = utf8.decode(res.bodyBytes);
    if (res.statusCode != 200) {
      String msg = text;
      try {
        msg = '${((jsonDecode(text) as Map)['error'] as Map)['message']}';
      } catch (_) {}
      throw LlmException(msg, statusCode: res.statusCode);
    }
    return (jsonDecode(text) as Map).cast<String, dynamic>();
  }

  /// Gemini: generateContent 를 지원하는 모델만 (임베딩·이미지 전용 등 제외).
  Future<List<String>> gemini(String apiKey) async {
    final out = <String>[];
    String? page;
    do {
      final j = await _get(
        Uri.https('generativelanguage.googleapis.com', '/v1beta/models', {
          'pageSize': '1000',
          'pageToken': ?page,
        }),
        {'x-goog-api-key': apiKey},
      );
      for (final m in (j['models'] as List? ?? const [])) {
        final methods = ((m as Map)['supportedGenerationMethods'] as List? ?? const []);
        if (methods.contains('generateContent')) {
          out.add('${m['name']}'.replaceFirst('models/', ''));
        }
      }
      page = j['nextPageToken'] as String?;
    } while (page != null && page.isNotEmpty);
    return _sorted(out);
  }

  /// OpenAI·Grok: 대화용 모델만 (임베딩·음성·이미지 모델 제외).
  Future<List<String>> openai(String apiKey, {String baseUrl = 'https://api.openai.com/v1'}) async {
    final j = await _get(Uri.parse('$baseUrl/models'), {'authorization': 'Bearer $apiKey'});
    final skip = RegExp(
      r'(embedding|whisper|tts|audio|dall-e|image|moderation|transcribe|realtime|search)',
    );
    return _sorted([
      for (final m in (j['data'] as List? ?? const []))
        if (!skip.hasMatch('${(m as Map)['id']}')) '${m['id']}',
    ]);
  }

  Future<List<String>> grok(String apiKey) => openai(apiKey, baseUrl: 'https://api.x.ai/v1');

  /// OpenRouter: 도구 호출(tools)을 지원하는 모델만, 무료 모델을 위로.
  Future<List<String>> openRouter(String apiKey) async {
    final j = await _get(Uri.parse('https://openrouter.ai/api/v1/models'), {
      if (apiKey.isNotEmpty) 'authorization': 'Bearer $apiKey',
    });
    final ids = [
      for (final m in (j['data'] as List? ?? const []))
        if (((m as Map)['supported_parameters'] as List? ?? const []).contains('tools'))
          '${m['id']}',
    ];
    final free = _sorted(ids.where((i) => i.endsWith(':free')).toList());
    final paid = _sorted(ids.where((i) => !i.endsWith(':free')).toList());
    return ['openrouter/free', ...free, ...paid];
  }

  Future<List<String>> anthropic(String apiKey, {String? workspaceId}) async {
    final j = await _get(Uri.parse('https://api.anthropic.com/v1/models?limit=1000'), {
      'x-api-key': apiKey,
      'anthropic-version': '2023-06-01',
      if (workspaceId?.isNotEmpty ?? false) 'anthropic-workspace-id': workspaceId!,
    });
    return _sorted([for (final m in (j['data'] as List? ?? const [])) '${(m as Map)['id']}']);
  }

  /// 최신(버전 숫자가 큰) 모델이 위로 오도록.
  static List<String> _sorted(List<String> ids) =>
      ids.toSet().toList()..sort((a, b) => b.compareTo(a));
}
