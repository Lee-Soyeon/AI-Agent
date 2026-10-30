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
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: tabListPadding(context).copyWith(left: 24, right: 24, top: 32),
          children: [
            if (agent.isBusy) ...[ActiveTaskBanner(agent: agent), const SizedBox(height: 16)],
            Text(name.isEmpty ? '무엇을 맡길까요?' : '$name님,\n무엇을 맡길까요?', style: MontageType.title2().copyWith(color: t.ink)),
            const SizedBox(height: 8),
            Text('가진 걸 넣으면 할 수 있는 일을 골라 드려요', style: MontageType.body1Reading().copyWith(color: t.muted)),
            const SizedBox(height: 24),
            Row(
              children: [
                _InputTile(icon: Icons.photo_camera_outlined, label: '사진', onTap: () => _intake('photo')),
                const SizedBox(width: 8),
                _InputTile(icon: Icons.insert_drive_file_outlined, label: '파일', onTap: () => _intake('file')),
                const SizedBox(width: 8),
                _InputTile(icon: Icons.notes, label: '글', onTap: () => _intake('text')),
              ],
            ),
            const SizedBox(height: 48),
            Text('이런 일을 맡길 수 있어요', style: MontageType.heading1().copyWith(color: t.ink)),
            const SizedBox(height: 8),
            for (final r in recipes) RecipeRow(recipe: r, pick: r == today && settings.routine.isNotEmpty),
            if (others.isNotEmpty)
              Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  iconColor: t.muted,
                  collapsedIconColor: t.muted,
                  title: Text('다른 일 더 보기', style: MontageType.body2(MontageType.medium).copyWith(color: t.muted)),
                  children: [for (final r in others) RecipeRow(recipe: r)],
                ),
              ),
            const SizedBox(height: 40),
            Text('찾는 일이 없나요?', style: MontageType.heading1().copyWith(color: t.ink)),
            const SizedBox(height: 12),
            Row(
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
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

/// 넣기 타일: Montage surface.neutral.secondary 면 + line.neutral.tertiary 선.
class _InputTile extends StatelessWidget {
  const _InputTile({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppTokens.rSm),
      side: BorderSide(color: t.line),
    );
    return Expanded(
      child: Material(
        color: t.tint,
        shape: shape,
        child: InkWell(
          customBorder: shape,
          onTap: onTap,
          child: SizedBox(
            height: 96,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: t.ink, size: 26),
                const SizedBox(height: 10),
                Text(label, style: MontageType.body2(MontageType.semibold).copyWith(color: t.ink)),
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

/// 할 일 한 줄: 제목 · 무엇을 하는지 한 문장 · 화살표. 반복하는 일과 맞으면 "추천".
class RecipeRow extends StatelessWidget {
  const RecipeRow({super.key, required this.recipe, this.pick = false});

  final Recipe recipe;
  final bool pick;

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return InkWell(
      onTap: () => startRecipe(context, recipe),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.line))),
        child: Row(
          children: [
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
                          style: MontageType.headline2().copyWith(color: t.ink),
                        ),
                      ),
                      if (pick) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: t.tint, borderRadius: BorderRadius.circular(6)),
                          child: Text('추천', style: MontageType.caption1(MontageType.semibold).copyWith(color: t.ink)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    recipe.can,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: MontageType.label1().copyWith(color: t.muted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Icon(Icons.chevron_right, size: 22, color: t.muted),
          ],
        ),
      ),
    );
  }
}
