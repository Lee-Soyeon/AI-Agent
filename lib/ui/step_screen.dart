import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../agent/agent_controller.dart';
import '../agent/intake_content.dart';
import '../agent/task_intake.dart';
import '../recipes/recipe_catalog.dart';
import 'confirm_screen.dart';
import 'intake_picker.dart';
import 'toss_form.dart';

/// 레시피를 열어 단계 화면부터 시작한다. 단계가 없으면 바로 확인 화면.
Future<void> startRecipe(BuildContext context, Recipe recipe, {IntakeContent? content}) {
  final intake = TaskIntake(recipe, content: content);
  final nav = Navigator.of(context);
  if (intake.isDone) return nav.push(MaterialPageRoute(builder: (_) => ConfirmScreen(intake: intake)));
  return nav.push(MaterialPageRoute(builder: (_) => StepScreen(intake: intake)));
}

/// 단계 화면 하나 (PRD 4.1, 5.3). 질문 한 줄 · 왜 묻는지 · 칩 또는 키워드 또는 큰 버튼.
class StepScreen extends StatefulWidget {
  const StepScreen({super.key, required this.intake});

  final TaskIntake intake;

  @override
  State<StepScreen> createState() => _StepScreenState();
}

class _StepScreenState extends State<StepScreen> {
  final _field = TextEditingController();
  bool _free = false;
  bool _busy = false;

  TaskIntake get intake => widget.intake;

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _advance() {
    _field.clear();
    _free = false;
    if (intake.isDone) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => ConfirmScreen(intake: intake)));
      return;
    }
    setState(() {});
  }

  void _answer(String v) {
    if (v.trim().isEmpty) return;
    intake.answer(v);
    _advance();
  }

  Future<void> _pick(String accept) async {
    setState(() => _busy = true);
    try {
      final c = await pickIntakeContent(context, accept);
      if (c == null) return;
      intake.answerContent(c);
      _advance();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = intake.step;
    if (s == null) return const SizedBox.shrink();
    final agent = context.read<AgentController>();
    final options = intake.optionsFor(s);

    final (Widget body, bool chipsOnly, bool canNext) = switch (s.kind) {
      'chips' => (
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TossChips(
              options: options,
              allowFree: s.allowFree,
              freeSelected: _free,
              onSelected: _answer,
              onFree: () => setState(() => _free = true),
            ),
            if (_free) ...[
              const SizedBox(height: 14),
              TossKeywordField(controller: _field, placeholder: s.placeholder, onSubmitted: _answer, onChanged: (_) => setState(() {})),
            ],
          ],
        ),
        !_free,
        _free && _field.text.trim().isNotEmpty,
      ),
      'keyword' => (
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (options.isNotEmpty) ...[
              TossChips(options: options, onSelected: _answer),
              const SizedBox(height: 14),
            ],
            TossKeywordField(controller: _field, placeholder: s.placeholder, onSubmitted: _answer, onChanged: (_) => setState(() {})),
          ],
        ),
        false,
        _field.text.trim().isNotEmpty,
      ),
      'text' => (
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TossKeywordField(
              controller: _field,
              placeholder: s.placeholder ?? '여기에 붙여 넣어 주세요',
              maxLines: 8,
              onChanged: (_) => setState(() {}),
            ),
            if (s.button != null) ...[
              const SizedBox(height: 14),
              TossBigButton(
                label: s.button!,
                icon: Icons.photo_camera_outlined,
                filled: false,
                onPressed: _busy ? null : () => _pick('photo'),
              ),
            ],
          ],
        ),
        false,
        _field.text.trim().isNotEmpty,
      ),
      // file | photo
      _ => (
        TossBigButton(
          label: s.button ?? (s.kind == 'photo' ? '사진 찍기' : '파일 올리기'),
          icon: s.kind == 'photo' ? Icons.photo_camera_outlined : Icons.upload_file_outlined,
          onPressed: _busy ? null : () => _pick(s.accept ?? s.kind),
        ),
        true,
        false,
      ),
    };

    return TossFormScaffold(
      step: intake.position,
      total: intake.total,
      question: s.text,
      why: s.why,
      assembled: intake.assembled,
      onBack: () {
        if (intake.back()) {
          _field.clear();
          _free = false;
          setState(() {});
        } else {
          Navigator.of(context).maybePop();
        }
      },
      trailing: agent.isBusy
          ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
          : null,
      hideNext: chipsOnly,
      onNext: canNext
          ? () {
              if (s.kind == 'text') {
                intake.answerContent(IntakeContent.text(_field.text, name: s.text));
                _advance();
              } else {
                _answer(_field.text);
              }
            }
          : null,
      child: body,
    );
  }
}
