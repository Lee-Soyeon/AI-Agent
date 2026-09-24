import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/settings_store.dart';
import '../llm/model_list.dart';
import '../remote/agent_server_client.dart';
import 'chatgpt_login.dart';
import 'app_theme.dart';
import 'main_shell.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late LlmVendor _vendor;
  late final Map<LlmVendor, TextEditingController> _keys;
  late final Map<LlmVendor, TextEditingController> _models;
  late final TextEditingController _maxSteps;
  late final TextEditingController _workspaceId;
  late bool _runOnServer;
  late final TextEditingController _serverUrl;
  late final TextEditingController _serverToken;
  String? _serverTest;
  bool _serverOk = false;
  bool _testing = false;
  final Set<LlmVendor> _revealed = {};

  @override
  void initState() {
    super.initState();
    final s = context.read<SettingsStore>();
    _vendor = s.vendor;
    _keys = {for (final v in LlmVendor.values) v: TextEditingController(text: s.apiKey(v))};
    _models = {for (final v in LlmVendor.values) v: TextEditingController(text: s.model(v))};
    _maxSteps = TextEditingController(text: '${s.maxSteps}');
    _workspaceId = TextEditingController(text: s.anthropicWorkspaceId);
    _runOnServer = s.runOnServer;
    _serverUrl = TextEditingController(text: s.serverUrl);
    _serverToken = TextEditingController(text: s.serverToken);
  }

  @override
  void dispose() {
    for (final c in [
      ..._keys.values,
      ..._models.values,
      _maxSteps,
      _serverUrl,
      _serverToken,
      _workspaceId,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  /// 입력한 API 키로 공급자에게 모델 목록을 물어보고 골라서 넣는다.
  Future<void> _pickModel(LlmVendor v) async {
    final key = _keys[v]!.text.trim();
    if (key.isEmpty && v != LlmVendor.openrouter) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('먼저 API 키를 입력하세요.')));
      return;
    }
    final lister = ModelLister();
    final future = switch (v) {
      LlmVendor.gemini => lister.gemini(key),
      LlmVendor.openai => lister.openai(key),
      LlmVendor.anthropic => lister.anthropic(key, workspaceId: _workspaceId.text.trim()),
      LlmVendor.grok => lister.grok(key),
      LlmVendor.openrouter => lister.openRouter(key),
      LlmVendor.chatgpt => Future.value(const <String>[]),
    };
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (context, scroll) => FutureBuilder<List<String>>(
          future: future,
          builder: (context, snap) {
            if (snap.hasError) {
              return Padding(
                padding: const EdgeInsets.all(24),
                child: Text('모델 목록을 불러오지 못했습니다.\n${snap.error}'),
              );
            }
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final models = snap.data!;
            return ListView(
              controller: scroll,
              children: [
                ListTile(
                  title: Text('${v.label} — 이 키로 쓸 수 있는 모델 ${models.length}개'),
                  subtitle: const Text(
                    '에이전트는 도구 호출이 되는 모델이 필요합니다. 이름에 flash·lite·mini 가 붙은 모델이 싸고 빠릅니다.',
                  ),
                ),
                for (final m in models)
                  ListTile(
                    dense: true,
                    title: Text(m),
                    trailing: m == _models[v]!.text ? const Icon(Icons.check) : null,
                    onTap: () => Navigator.pop(context, m),
                  ),
              ],
            );
          },
        ),
      ),
    );
    if (picked != null) setState(() => _models[v]!.text = picked);
  }

  Future<void> _testServer() async {
    setState(() {
      _testing = true;
      _serverTest = null;
    });
    try {
      await AgentServerClient(
        baseUrl: _serverUrl.text.trim(),
        token: _serverToken.text.trim(),
      ).ping();
      _serverTest = '연결 성공';
      _serverOk = true;
    } catch (e) {
      _serverTest = '연결 실패: $e';
      _serverOk = false;
    }
    if (mounted) setState(() => _testing = false);
  }

  Future<void> _save() async {
    final store = context.read<SettingsStore>();
    await store.saveServer(
      runOnServer: _runOnServer,
      url: _serverUrl.text,
      token: _serverToken.text,
    );
    if (!mounted) return;
    await context.read<SettingsStore>().save(
      vendor: _vendor,
      apiKeys: {for (final e in _keys.entries) e.key: e.value.text},
      models: {for (final e in _models.entries) e.key: e.value.text},
      maxSteps: (int.tryParse(_maxSteps.text) ?? 60).clamp(5, 200),
      anthropicWorkspaceId: _workspaceId.text,
    );
    if (!mounted) return;
    FocusScope.of(context).unfocus();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('저장했어요')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('모델 설정'),
        actions: [TextButton(onPressed: _save, child: const Text('저장'))],
      ),
      body: ListView(
        padding: tabListPadding(context),
        children: [
          Text('실행 위치', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, icon: Icon(Icons.phone_iphone), label: Text('이 폰')),
              ButtonSegment(value: true, icon: Icon(Icons.cloud), label: Text('서버 (백그라운드)')),
            ],
            selected: {_runOnServer},
            onSelectionChanged: (v) => setState(() => _runOnServer = v.first),
          ),
          const SizedBox(height: 8),
          Text(
            _runOnServer
                ? '작업이 서버의 크롬 브라우저에서 실행됩니다. 앱을 꺼도 계속되고, 어떤 웹 서비스든 다룰 수 있습니다. '
                      'LLM 은 서버에 설정한 API 키를 씁니다. (server/README.md 참고)'
                : '작업이 이 폰의 보이지 않는 브라우저와 Gmail API 로 실행됩니다. 앱을 내리면 멈출 수 있습니다.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (_runOnServer) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _serverUrl,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: '서버 주소',
                hintText: 'https://agent.example.com',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _serverToken,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(labelText: '서버 토큰 (AGENT_TOKEN)'),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                OutlinedButton(
                  onPressed: _testing ? null : _testServer,
                  child: Text(_testing ? '확인 중…' : '연결 테스트'),
                ),
                const SizedBox(width: 12),
                if (_serverTest != null)
                  Expanded(
                    child: Text(
                      _serverTest!,
                      style: TextStyle(
                        color: _serverOk
                            ? AppTokens.of(context).accent
                            : AppTokens.of(context).errorInk,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ],
          const Divider(height: 40),
          Text(
            _runOnServer ? '이 폰에서 쓸 LLM (말투 학습 등)' : '사용할 LLM',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final v in LlmVendor.values)
                ChoiceChip(
                  label: Text(v.label),
                  selected: _vendor == v,
                  onSelected: (_) => setState(() => _vendor = v),
                ),
            ],
          ),
          const SizedBox(height: 24),
          for (final v in LlmVendor.values) ...[
            Text(v.label, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            if (!v.usesApiKey)
              const ChatGptAccountTile()
            else
              TextField(
                controller: _keys[v],
                obscureText: !_revealed.contains(v),
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: 'API 키',
                  suffixIcon: IconButton(
                    icon: Icon(_revealed.contains(v) ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(
                      () => _revealed.contains(v) ? _revealed.remove(v) : _revealed.add(v),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            TextField(
              controller: _models[v],
              autocorrect: false,
              decoration: InputDecoration(
                labelText: '모델',
                helperText: '기본값: ${v.defaultModel}',
                suffixIcon: v.usesApiKey
                    ? IconButton(
                        tooltip: '사용 가능한 모델 목록',
                        icon: const Icon(Icons.format_list_bulleted),
                        onPressed: () => _pickModel(v),
                      )
                    : null,
              ),
            ),
            if (v == LlmVendor.anthropic) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _workspaceId,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: '워크스페이스 ID (선택)',
                  helperText: '"not scoped to a workspace" 오류가 날 때만 입력 (wrkspc_…)',
                ),
              ),
            ],
            const SizedBox(height: 24),
          ],
          TextField(
            controller: _maxSteps,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: '작업당 최대 단계 수',
              helperText: '에이전트가 무한히 돌지 않도록 제한합니다',
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'API 키는 기기의 보안 저장소(iOS Keychain / Android Keystore)에만 저장되며, '
            '각 LLM 공급자에게 직접 전송됩니다. 사이트 비밀번호는 앱이 저장하지 않습니다.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
