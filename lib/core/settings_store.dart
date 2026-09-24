import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../llm/anthropic_provider.dart';
import '../llm/chatgpt_codex_provider.dart';
import '../llm/gemini_provider.dart';
import '../llm/llm_types.dart';
import '../llm/openai_provider.dart';
import '../openai/chatgpt_auth.dart';
import '../remote/agent_server_client.dart';

enum LlmVendor {
  openai('OpenAI API', 'gpt-4.1'),
  chatgpt('ChatGPT 구독 (Plus/Pro)', 'gpt-5.5', usesApiKey: false),
  anthropic('Claude (Anthropic)', 'claude-sonnet-5'),
  gemini('Gemini (Google)', 'gemini-2.5-flash');

  const LlmVendor(this.label, this.defaultModel, {this.usesApiKey = true});

  final String label;
  final String defaultModel;

  /// false 면 API 키 대신 계정 로그인으로 인증한다.
  final bool usesApiKey;
}

/// API 키는 기기 보안 저장소(Keychain / Keystore)에, 나머지 설정은 SharedPreferences 에 저장한다.
class SettingsStore extends ChangeNotifier {
  SettingsStore({required this.chatgpt, FlutterSecureStorage? secure})
    : _secure = secure ?? const FlutterSecureStorage();

  final ChatGptAuth chatgpt;
  final FlutterSecureStorage _secure;

  LlmVendor vendor = LlmVendor.anthropic;
  final Map<LlmVendor, String> _apiKeys = {};
  final Map<LlmVendor, String> _models = {};
  int maxSteps = 60;

  /// 선택: 워크스페이스에 속하지 않은 Anthropic 키용 워크스페이스 ID.
  String anthropicWorkspaceId = '';

  /// true 면 작업을 서버(server/)의 브라우저에서 백그라운드로 실행한다.
  bool runOnServer = false;
  String serverUrl = '';
  String serverToken = '';

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    vendor = LlmVendor.values.firstWhere(
      (v) => v.name == prefs.getString('vendor'),
      orElse: () => LlmVendor.anthropic,
    );
    maxSteps = prefs.getInt('maxSteps') ?? 60;
    anthropicWorkspaceId = prefs.getString('anthropicWorkspaceId') ?? '';
    runOnServer = prefs.getBool('runOnServer') ?? false;
    serverUrl = prefs.getString('serverUrl') ?? '';
    try {
      serverToken = await _secure.read(key: 'serverToken') ?? '';
    } catch (_) {
      serverToken = '';
    }
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

  /// 폰에서 실행할 때의 LLM 설정이 됐는지.
  bool get isLocalLlmConfigured =>
      vendor.usesApiKey ? apiKey(vendor).isNotEmpty : chatgpt.isSignedIn;

  bool get isServerConfigured => serverUrl.isNotEmpty && serverToken.isNotEmpty;

  /// 작업을 시작할 수 있는지 (서버 모드면 LLM 은 서버가 가진 키를 쓴다).
  bool get isConfigured => runOnServer ? isServerConfigured : isLocalLlmConfigured;

  AgentServerClient? get serverClient =>
      isServerConfigured ? AgentServerClient(baseUrl: serverUrl, token: serverToken) : null;

  Future<void> saveServer({
    required bool runOnServer,
    required String url,
    required String token,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    this.runOnServer = runOnServer;
    serverUrl = url.trim().replaceAll(RegExp(r'/+$'), '');
    serverToken = token.trim();
    await prefs.setBool('runOnServer', runOnServer);
    await prefs.setString('serverUrl', serverUrl);
    await _secure.write(key: 'serverToken', value: serverToken);
    notifyListeners();
  }

  Future<void> save({
    required LlmVendor vendor,
    required Map<LlmVendor, String> apiKeys,
    required Map<LlmVendor, String> models,
    required int maxSteps,
    String anthropicWorkspaceId = '',
  }) async {
    final prefs = await SharedPreferences.getInstance();
    this.vendor = vendor;
    this.maxSteps = maxSteps;
    this.anthropicWorkspaceId = anthropicWorkspaceId.trim();
    await prefs.setString('anthropicWorkspaceId', this.anthropicWorkspaceId);
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
      LlmVendor.chatgpt => ChatGptCodexProvider(auth: chatgpt, model: m),
      LlmVendor.anthropic => AnthropicProvider(
        apiKey: key,
        model: m,
        workspaceId: anthropicWorkspaceId,
      ),
      LlmVendor.gemini => GeminiProvider(apiKey: key, model: m),
    };
  }
}
