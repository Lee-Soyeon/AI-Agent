import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/settings_store.dart';

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
  final Set<LlmVendor> _revealed = {};

  @override
  void initState() {
    super.initState();
    final s = context.read<SettingsStore>();
    _vendor = s.vendor;
    _keys = {for (final v in LlmVendor.values) v: TextEditingController(text: s.apiKey(v))};
    _models = {for (final v in LlmVendor.values) v: TextEditingController(text: s.model(v))};
    _maxSteps = TextEditingController(text: '${s.maxSteps}');
  }

  @override
  void dispose() {
    for (final c in [..._keys.values, ..._models.values, _maxSteps]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    await context.read<SettingsStore>().save(
      vendor: _vendor,
      apiKeys: {for (final e in _keys.entries) e.key: e.value.text},
      models: {for (final e in _models.entries) e.key: e.value.text},
      maxSteps: (int.tryParse(_maxSteps.text) ?? 60).clamp(5, 200),
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('설정'),
        actions: [TextButton(onPressed: _save, child: const Text('저장'))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('사용할 LLM', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SegmentedButton<LlmVendor>(
            segments: const [
              ButtonSegment(value: LlmVendor.openai, label: Text('OpenAI')),
              ButtonSegment(value: LlmVendor.anthropic, label: Text('Claude')),
              ButtonSegment(value: LlmVendor.gemini, label: Text('Gemini')),
            ],
            selected: {_vendor},
            onSelectionChanged: (s) => setState(() => _vendor = s.first),
          ),
          const SizedBox(height: 24),
          for (final v in LlmVendor.values) ...[
            Text(v.label, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            TextField(
              controller: _keys[v],
              obscureText: !_revealed.contains(v),
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: 'API 키',
                border: const OutlineInputBorder(),
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
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
          ],
          TextField(
            controller: _maxSteps,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: '작업당 최대 단계 수',
              helperText: '에이전트가 무한히 돌지 않도록 제한합니다',
              border: OutlineInputBorder(),
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
