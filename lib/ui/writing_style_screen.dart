import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../agent/agent_controller.dart';
import '../core/settings_store.dart';
import '../google/writing_style.dart';

/// 보낸 메일로 학습한 말투 가이드를 보고, 고치고, 다시 학습하는 화면.
class WritingStyleScreen extends StatefulWidget {
  const WritingStyleScreen({super.key});

  @override
  State<WritingStyleScreen> createState() => _WritingStyleScreenState();
}

class _WritingStyleScreenState extends State<WritingStyleScreen> {
  final _guide = TextEditingController();
  bool _editing = false;

  @override
  void dispose() {
    _guide.dispose();
    super.dispose();
  }

  Future<void> _learn() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('내 말투 학습'),
        content: const Text(
          '보낸편지함의 최근 메일 최대 50통을 읽어, 현재 선택한 LLM 에 보내 말투를 분석합니다.\n\n'
          '메일 내용이 LLM 공급자에게 전송된다는 점을 확인해 주세요. '
          '분석 결과는 이 기기의 보안 저장소에만 저장됩니다.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('학습 시작')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _editing = false);
    await context.read<AgentController>().learnWritingStyle();
  }

  @override
  Widget build(BuildContext context) {
    final style = context.watch<WritingStyleStore>();
    final settings = context.watch<SettingsStore>();
    final profile = style.profile;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('내 메일 말투'),
        actions: [
          if (profile != null && !style.busy)
            _editing
                ? TextButton(
                    onPressed: () async {
                      await style.updateGuide(_guide.text);
                      if (mounted) setState(() => _editing = false);
                    },
                    child: const Text('저장'),
                  )
                : IconButton(
                    tooltip: '직접 고치기',
                    icon: const Icon(Icons.edit),
                    onPressed: () => setState(() {
                      _guide.text = profile.guide;
                      _editing = true;
                    }),
                  ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '에이전트가 메일을 쓸 때 이 가이드와, 같은 사람에게 예전에 보낸 메일을 함께 참고해 '
            '인사말·호칭·어미·서명까지 내가 쓴 것처럼 작성합니다.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          if (style.busy)
            Card(
              child: ListTile(
                leading: const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                title: Text(style.progress ?? '학습 중…'),
              ),
            )
          else
            FilledButton.icon(
              onPressed: settings.isLocalLlmConfigured ? _learn : null,
              icon: const Icon(Icons.auto_fix_high),
              label: Text(profile == null ? '보낸 메일로 말투 학습하기' : '다시 학습하기'),
            ),
          if (!settings.isLocalLlmConfigured)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('먼저 설정에서 LLM 을 연결하세요.', style: theme.textTheme.bodySmall),
            ),
          if (style.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(style.error!, style: TextStyle(color: theme.colorScheme.error)),
            ),
          const SizedBox(height: 16),
          if (profile != null) ...[
            Text(
              '보낸 메일 ${profile.analyzedCount}통 분석 · '
              '${profile.updatedAt.toLocal().toString().substring(0, 16)}',
              style: theme.textTheme.labelMedium,
            ),
            const SizedBox(height: 8),
            if (_editing)
              TextField(
                controller: _guide,
                maxLines: null,
                minLines: 12,
                decoration: const InputDecoration(border: OutlineInputBorder()),
              )
            else
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: SelectableText(profile.guide),
                ),
              ),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: style.busy ? null : style.clear,
              icon: const Icon(Icons.delete_outline),
              label: const Text('학습한 말투 지우기'),
            ),
          ],
        ],
      ),
    );
  }
}
