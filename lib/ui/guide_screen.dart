import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../agent/agent_controller.dart';
import '../agent/intake_content.dart';
import '../core/settings_store.dart';
import '../google/google_auth.dart';
import '../recipes/recipe_catalog.dart';
import '../remote/agent_server_client.dart';
import '../ui_parts/ui_part.dart';
import 'app_theme.dart';
import 'confirm_screen.dart';
import 'intake_picker.dart';
import 'main_shell.dart' show tabListPadding;
import 'step_screen.dart';
import 'task_screen.dart';
import 'toss_form.dart';
import 'ui_renderer.dart';

/// 홈 탭 (PRD 4.3, 5.2). 묻지 않는다. 보여준다.
///
/// 위에서 아래로: 인사 · 가진 걸 넣기(사진·파일·글) · 맡길 수 있는 일 목록(내 직업 것, 추천 먼저) · 찾는 일이 없나요.
class GuideScreen extends StatefulWidget {
  const GuideScreen({super.key});

  @override
  State<GuideScreen> createState() => _GuideScreenState();
}

class _GuideScreenState extends State<GuideScreen> {
  final _other = TextEditingController();

  @override
  void dispose() {
    _other.dispose();
    super.dispose();
  }

  Future<void> _intake(String accept) async {
    final content = await pickIntakeContent(context, accept);
    if (content == null || !mounted) return;
    await showIntakeChips(context, content);
  }

  Future<void> _startOther(String text) async {
    final t = text.trim();
    if (t.isEmpty) return;
    if (!await ConfirmScreen.ensureReady(context)) return;
    if (!mounted) return;
    final agent = context.read<AgentController>();
    if (agent.isBusy) return;
    _other.clear();
    agent.startTask(t);
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TaskScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsStore>();
    final agent = context.watch<AgentController>();
    final google = context.watch<GoogleAuthService>();
    final catalog = context.read<RecipeCatalog?>() ?? RecipeCatalog.empty();
    final t = AppTokens.of(context);
    final today = catalog.todays(null, settings.persona, settings.routine);
    final recipes = [
      ?today,
      ...catalog.forPersona(settings.persona, routine: settings.routine).where((r) => r != today),
    ];
    final others = catalog.othersFor(settings.persona);
    final name = (google.name ?? '').trim().split(RegExp(r'\s+')).first;

    return Scaffold(
      backgroundColor: t.line,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: tabListPadding(context).copyWith(top: 28),
          children: [
            if (agent.isBusy) ...[ActiveTaskBanner(agent: agent), const SizedBox(height: 12)],
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                name.isEmpty ? '무엇을 맡길까요?' : '$name님,\n무엇을 맡길까요?',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, height: 1.35, letterSpacing: -0.6, color: t.ink),
              ),
            ),
            const SizedBox(height: 20),
            _Section(
              title: '가진 걸 넣어 주세요',
              sub: '넣으면 그걸로 할 수 있는 일을 골라 드려요',
              child: Row(
                children: [
                  _InputTile(icon: Icons.photo_camera_outlined, label: '사진', onTap: () => _intake('photo')),
                  const SizedBox(width: 8),
                  _InputTile(icon: Icons.insert_drive_file_outlined, label: '파일', onTap: () => _intake('file')),
                  const SizedBox(width: 8),
                  _InputTile(icon: Icons.notes, label: '글', onTap: () => _intake('text')),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _Section(
              title: '이런 일을 맡길 수 있어요',
              padding: const EdgeInsets.fromLTRB(0, 20, 0, 8),
              child: Column(
                children: [
                  for (final r in recipes) RecipeRow(recipe: r, pick: r == today && settings.routine.isNotEmpty),
                  if (others.isNotEmpty)
                    Theme(
                      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        tilePadding: const EdgeInsets.symmetric(horizontal: 20),
                        title: Text('다른 일 더 보기', style: TextStyle(color: t.muted, fontSize: 15, fontWeight: FontWeight.w600)),
                        children: [for (final r in others) RecipeRow(recipe: r)],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _Section(
              title: '찾는 일이 없나요?',
              child: Row(
                children: [
                  Expanded(
                    child: TossKeywordField(
                      controller: _other,
                      autofocus: false,
                      placeholder: '예: 영수증 사진 정리',
                      onSubmitted: _startOther,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(icon: const Icon(Icons.arrow_forward), onPressed: () => _startOther(_other.text)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 토스 홈의 흰 묶음: 회색 바탕 위 둥근 흰 면, 테두리 없음.
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.sub, this.padding = const EdgeInsets.all(20)});

  final String title;
  final String? sub;
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Container(
      decoration: BoxDecoration(color: t.paper, borderRadius: BorderRadius.circular(AppTokens.r)),
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: padding.left == 0 ? 20 : 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: -0.3, color: t.ink)),
                if (sub != null) ...[
                  const SizedBox(height: 4),
                  Text(sub!, style: TextStyle(fontSize: 14, color: t.muted)),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _InputTile extends StatelessWidget {
  const _InputTile({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Expanded(
      child: Material(
        color: t.accentSoft,
        borderRadius: BorderRadius.circular(AppTokens.rSm),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTokens.rSm),
          onTap: onTap,
          child: SizedBox(
            height: 88,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: t.accent, size: 28),
                const SizedBox(height: 8),
                Text(label, style: TextStyle(color: t.accent, fontSize: 15, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 넣은 내용으로 "이걸로 할 수 있는 일" 칩 3개를 띄운다. 서버가 3초 안에 안 주면 기본 칩.
Future<void> showIntakeChips(BuildContext context, IntakeContent content) async {
  final catalog = context.read<RecipeCatalog?>() ?? RecipeCatalog.empty();
  final settings = context.read<SettingsStore>();
  final client = settings.runOnServer ? settings.serverClient : null;
  final defaults = catalog.intakeDefaults(content.kind);
  final nav = Navigator.of(context);

  final chips = ValueNotifier<UiPart?>(null);
  String? summary;
  unawaited(() async {
    List<String> options = defaults;
    if (client != null) {
      try {
        final j = await client.intake(content.toIntakeJson());
        final ui = j?['ui'];
        if (ui is Map) {
          final part = UiPart.fromJson(ui);
          if (part.type == UiPartType.chips && part.options.length >= 2) {
            options = part.options;
            summary = j?['summary'] as String?;
          }
        }
      } on AgentServerException catch (e) {
        if (e.statusCode == 429) summary = e.message;
      } catch (_) {
        // 늦거나 실패하면 기본 칩
      }
    }
    chips.value = UiPart.fromJson({
      'type': 'chips',
      'question': '이걸로 할 수 있는 일',
      'why': summary ?? content.name,
      'options': options.take(6).toList(),
      'allow_free': true,
      'placeholder': '예: 표로 정리해줘',
    });
  }());

  final picked = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 16 + MediaQuery.viewInsetsOf(ctx).bottom),
        child: ValueListenableBuilder<UiPart?>(
          valueListenable: chips,
          builder: (_, part, _) => part == null
              ? const _SkeletonChips()
              : UiPartView(part: part, onAnswer: (v) => Navigator.pop(ctx, v)),
        ),
      ),
    ),
  );
  chips.dispose();
  if (picked == null || !context.mounted) return;

  final recipe = catalog.find(picked) ??
      Recipe.synthetic(
        title: picked,
        promptTemplate: '$picked: 넣은 내용으로 해줘. 결과는 표나 목록으로 보여줘. 내용: {content}',
      );
  if (!context.mounted) return;
  // 즉석 레시피는 단계가 없으니 바로 확인 화면. 레시피면 첫 내용 단계를 건너뛰고 다음 단계부터.
  unawaited(nav.maybePop().then((_) {
    if (context.mounted) startRecipe(context, recipe, content: content);
  }));
}

class _SkeletonChips extends StatelessWidget {
  const _SkeletonChips();

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('읽는 중…', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: t.ink)),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final w in [110.0, 90.0, 130.0])
              Container(
                width: w,
                height: 36,
                decoration: BoxDecoration(color: t.line, borderRadius: BorderRadius.circular(18)),
              ),
          ],
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

/// 할 일 한 줄: 동그란 아이콘 + 제목 + 무엇을 하는지 한 문장. 반복하는 일과 맞으면 "추천".
class RecipeRow extends StatelessWidget {
  const RecipeRow({super.key, required this.recipe, this.pick = false});

  final Recipe recipe;
  final bool pick;

  static IconData iconFor(String id) => switch (id) {
    _ when id.startsWith('doc_') => Icons.description_outlined,
    _ when id.startsWith('excel') => Icons.table_chart_outlined,
    _ when id.startsWith('photo') => Icons.photo_outlined,
    _ when id.startsWith('bible') => Icons.menu_book_outlined,
    _ when id.startsWith('notice') => Icons.campaign_outlined,
    _ when id.startsWith('shift') => Icons.calendar_month_outlined,
    _ when id.startsWith('resume') => Icons.edit_note,
    _ when id.startsWith('job') => Icons.work_outline,
    _ when id.startsWith('coupang') => Icons.shopping_bag_outlined,
    _ => Icons.auto_awesome_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return InkWell(
      onTap: () => startRecipe(context, recipe),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: t.line, shape: BoxShape.circle),
              child: Icon(iconFor(recipe.id), color: t.ink, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          recipe.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: t.ink),
                        ),
                      ),
                      if (pick) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: t.accentSoft, borderRadius: BorderRadius.circular(6)),
                          child: Text('추천', style: TextStyle(color: t.accent, fontSize: 11, fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    recipe.can,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13.5, color: t.muted),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: t.muted.withValues(alpha: 0.6)),
          ],
        ),
      ),
    );
  }
}
