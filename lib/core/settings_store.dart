import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../llm/anthropic_provider.dart';
import '../llm/gemini_provider.dart';
import '../llm/llm_types.dart';
import '../llm/openai_provider.dart';

enum LlmVendor {
  openai('OpenAI', 'gpt-4.1'),
  anthropic('Claude (Anthropic)', 'claude-sonnet-5'),
  gemini('Gemini (Google)', 'gemini-2.5-flash');

  const LlmVendor(this.label, this.defaultModel);

  final String label;
  final String defaultModel;
}

/// API 키는 기기 보안 저장소(Keychain / Keystore)에, 나머지 설정은 SharedPreferences 에 저장한다.
class SettingsStore extends ChangeNotifier {
  SettingsStore({FlutterSecureStorage? secure}) : _secure = secure ?? const FlutterSecureStorage();

  final FlutterSecureStorage _secure;

  LlmVendor vendor = LlmVendor.anthropic;
  final Map<LlmVendor, String> _apiKeys = {};
  final Map<LlmVendor, String> _models = {};
  int maxSteps = 60;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    vendor = LlmVendor.values.firstWhere(
      (v) => v.name == prefs.getString('vendor'),
      orElse: () => LlmVendor.anthropic,
    );
    maxSteps = prefs.getInt('maxSteps') ?? 60;
    for (final v in LlmVendor.values) {
      _models[v] = prefs.getString('model_${v.name}') ?? v.defaultModel;
      try {
        _apiKeys[v] = await _secure.read(key: 'apiKey_${v.name}') ?? '';
      } catch (_) {
        _apiKeys[v] = '';
      }
    }
    notifyListeners();
  }

  String apiKey(LlmVendor v) => _apiKeys[v] ?? '';
  String model(LlmVendor v) => _models[v] ?? v.defaultModel;

  bool get isConfigured => apiKey(vendor).isNotEmpty;

  Future<void> save({
    required LlmVendor vendor,
    required Map<LlmVendor, String> apiKeys,
    required Map<LlmVendor, String> models,
    required int maxSteps,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    this.vendor = vendor;
    this.maxSteps = maxSteps;
    await prefs.setString('vendor', vendor.name);
    await prefs.setInt('maxSteps', maxSteps);
    for (final v in LlmVendor.values) {
      final m = (models[v] ?? '').trim();
      _models[v] = m.isEmpty ? v.defaultModel : m;
      await prefs.setString('model_${v.name}', _models[v]!);
      final k = (apiKeys[v] ?? '').trim();
      _apiKeys[v] = k;
      await _secure.write(key: 'apiKey_${v.name}', value: k);
    }
    notifyListeners();
  }

  LlmProvider createProvider() {
    final key = apiKey(vendor);
    final m = model(vendor);
    return switch (vendor) {
      LlmVendor.openai => OpenAiProvider(apiKey: key, model: m),
      LlmVendor.anthropic => AnthropicProvider(apiKey: key, model: m),
      LlmVendor.gemini => GeminiProvider(apiKey: key, model: m),
    };
  }
}
