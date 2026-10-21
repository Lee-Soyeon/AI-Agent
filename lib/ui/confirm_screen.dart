import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../agent/agent_controller.dart';
import '../agent/task_intake.dart';
import '../core/settings_store.dart';
import '../ui_parts/ui_part.dart';
import 'main_shell.dart';
import 'task_screen.dart';
import 'toss_form.dart';
import 'ui_renderer.dart';

/// 확인 화면 "이렇게 시킬까요?" (PRD 5.3). 실행 · 고치기 · 복사.
class ConfirmScreen extends StatelessWidget {
  const ConfirmScreen({super.key, required this.intake});

  final TaskIntake intake;

  /// 실행 직전 한 번만: 이 작업에 필요한 설정이 없으면 안내 시트 (전체 체크리스트 금지).
  static Future<bool> ensureReady(BuildContext context) async {
    final settings = context.read<SettingsStore>();
    if (settings.isConfigured) return true;
    final go = await showModalBottomSheet<bool>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('서버 연결이 필요해요', style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                settings.runOnServer ? '설정에서 서버 주소와 토큰을 넣으면 바로 실행돼요.' : '설정에서 "계정 없이 시작" 을 켜 주세요.',
                style: Theme.of(ctx).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 52,
                child: FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('설정으로 가기')),
              ),
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('나중에')),
            ],
          ),
        ),
      ),
    );
    if (go == true && context.mounted) {
      context.read<ShellTabs>().go(AppTab.model);
      Navigator.of(context).popUntil((r) => r.isFirst);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final agent = context.watch<AgentController>();
    final part = UiPart.fromJson({'type': 'confirm', 'sentence': intake.sentence, 'title': '이렇게 시킬까요?'});
    return TossFormScaffold(
      step: intake.total,
      total: intake.total + 1,
      question: intake.recipe.title,
      why: intake.recipe.cannot.isEmpty ? null : '못 하는 것: ${intake.recipe.cannot}',
      onBack: () => Navigator.of(context).maybePop(),
      hideNext: true,
      child: agent.isBusy
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: Text('진행 중인 작업이 끝나면 실행할 수 있어요.')),
            )
          : UiPartView(
              key: ValueKey(intake.sentence),
              part: part,
              onAnswer: (sentence) async {
                if (!await ensureReady(context)) return;
                if (!context.mounted) return;
                final nav = Navigator.of(context);
                agent.lastRecipeId = intake.recipe.id;
                agent.startTask(sentence);
                nav.popUntil((r) => r.isFirst);
                nav.push(MaterialPageRoute(builder: (_) => const TaskScreen()));
              },
            ),
    );
  }
}
