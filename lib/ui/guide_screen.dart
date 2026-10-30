import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../agent/agent_controller.dart';
import '../agent/intake_content.dart';
import '../core/settings_store.dart';
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
/// 위에서 아래로: 오늘의 하나 · 내 것부터 넣기(사진·파일·글) · 이런 것도 돼요(갤러리) · 다른 일이 있어요(접힘).
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
    final catalog = context.read<RecipeCatalog?>() ?? RecipeCatalog.empty();
    final theme = Theme.of(context);
    final t = AppTokens.of(context);
    final today = catalog.todays(null, settings.persona, settings.routine);
    final recipes = catalog.forPersona(settings.persona, routine: settings.routine).where((r) => r != today).toList();
    final others = catalog.othersFor(settings.persona);

    return Scaffold(
      appBar: AppBar(title: const Text('AI Agent')),
      body: ListView(
        padding: tabListPadding(context),
        children: [
          if (agent.isBusy) ActiveTaskBanner(agent: agent),
          if (today != null) ...[
            Text('오늘의 하나', style: theme.textTheme.labelLarge?.copyWith(color: t.muted)),
            const SizedBox(height: 8),
            GalleryCard(recipe: today, large: true, onTap: () => startRecipe(context, today)),
            const SizedBox(height: 24),
          ],
          Text(
            '내 것부터 넣어 보세요',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.5, color: t.ink, height: 1.3),
          ),
          const SizedBox(height: 4),
          Text('넣으면 그걸로 할 수 있는 일을 바로 보여드려요', style: TextStyle(color: t.muted, fontSize: 14)),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: TossBigButton(label: '사진 찍기', icon: Icons.photo_camera_outlined, onPressed: () => _intake('photo'))),
              const SizedBox(width: 10),
              Expanded(child: TossBigButton(label: '파일 올리기', icon: Icons.upload_file_outlined, onPressed: () => _intake('file'))),
            ],
          ),
          const SizedBox(height: 10),
          TossBigButton(label: '글 붙여넣기', icon: Icons.content_paste, filled: false, onPressed: () => _intake('text')),
          const SizedBox(height: 28),
          Text('이런 것도 돼요', style: theme.textTheme.titleMedium),
          const SizedBox(height: 10),
          _RecipeGrid(recipes: recipes),
          if (others.isNotEmpty)
            Theme(
              data: theme.copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text('다른 일 더 보기', style: TextStyle(color: t.muted, fontSize: 15)),
                children: [_RecipeGrid(recipes: others)],
              ),
            ),
          const SizedBox(height: 16),
          Theme(
            data: theme.copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text('다른 일이 있어요', style: TextStyle(color: t.muted, fontSize: 15)),
              children: [
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
                const SizedBox(height: 8),
              ],
            ),
          ),
        ],
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

class _RecipeGrid extends StatelessWidget {
  const _RecipeGrid({required this.recipes});

  final List<Recipe> recipes;

  @override
  Widget build(BuildContext context) => GridView.builder(
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 2,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      mainAxisExtent: 92,
    ),
    itemCount: recipes.length,
    itemBuilder: (_, i) => GalleryCard(recipe: recipes[i], onTap: () => startRecipe(context, recipes[i])),
  );
}

/// 갤러리 카드 = 제목 + 한 줄. 전후 그림은 실제 결과물 캡처가 생기면 다시 넣는다 (PRD 4.3).
class GalleryCard extends StatelessWidget {
  const GalleryCard({super.key, required this.recipe, required this.onTap, this.large = false});

  final Recipe recipe;
  final VoidCallback onTap;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(AppTokens.rSm),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: t.paper,
          borderRadius: BorderRadius.circular(AppTokens.rSm),
          border: Border.all(color: t.lineStrong),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(14, large ? 16 : 12, 14, large ? 16 : 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    recipe.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: large ? 17 : 15, fontWeight: FontWeight.w700, color: t.ink),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    recipe.galleryLine,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: t.muted, fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
