import 'package:flutter/material.dart';

import 'app_theme.dart';

/// 토스 입력 폼 문법의 뼈대 (PRD 4.1).
///
/// 한 화면에 질문 하나(큰 제목) · "왜 묻는지" 한 줄 · 본문 · 하단 고정 버튼 하나 · 상단 뒤로와 진행 점.
/// [assembled] 가 있으면 제목 위에 지금까지 조립된 문장을 한 줄로 보여준다.
class TossFormScaffold extends StatelessWidget {
  const TossFormScaffold({
    super.key,
    required this.step,
    required this.total,
    required this.question,
    required this.child,
    this.why,
    this.assembled,
    this.onBack,
    this.onNext,
    this.nextLabel = '다음',
    this.trailing,
    this.hideNext = false,
  });

  final int step;
  final int total;
  final String question;
  final String? why;
  final String? assembled;
  final Widget child;
  final VoidCallback? onBack;

  /// null 이면 버튼이 비활성.
  final VoidCallback? onNext;
  final String nextLabel;
  final Widget? trailing;

  /// 칩을 누르면 바로 넘어가는 화면은 버튼을 숨겨도 된다.
  final bool hideNext;

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: onBack == null
            ? null
            : IconButton(icon: const Icon(Icons.arrow_back_ios_new, size: 20), onPressed: onBack),
        automaticallyImplyLeading: onBack != null,
        title: ProgressDots(step: step, total: total),
        centerTitle: true,
        actions: [?trailing],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                children: [
                  if (assembled != null && assembled!.trim().isNotEmpty) ...[
                    Text(
                      assembled!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: t.muted, fontSize: 13, height: 1.4),
                    ),
                    const SizedBox(height: 14),
                  ],
                  Text(
                    question,
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, height: 1.35, letterSpacing: -0.5, color: t.ink),
                  ),
                  if (why != null && why!.trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(why!, style: TextStyle(color: t.muted, fontSize: 14.5, height: 1.45)),
                  ],
                  const SizedBox(height: 28),
                  child,
                ],
              ),
            ),
            if (!hideNext)
              Padding(
                padding: EdgeInsets.fromLTRB(20, 8, 20, 12 + MediaQuery.viewInsetsOf(context).bottom),
                child: SizedBox(
                  height: 56,
                  child: FilledButton(
                    onPressed: onNext,
                    child: Text(nextLabel, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class ProgressDots extends StatelessWidget {
  const ProgressDots({super.key, required this.step, required this.total});

  final int step;
  final int total;

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    if (total <= 0) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < total; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: i == step ? 18 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: i <= step ? t.accent : t.lineStrong,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
      ],
    );
  }
}

/// 답 칩 묶음. [allowFree] 면 맨 뒤에 "직접 입력".
class TossChips extends StatelessWidget {
  const TossChips({
    super.key,
    required this.options,
    required this.onSelected,
    this.selected,
    this.allowFree = false,
    this.freeSelected = false,
    this.onFree,
  });

  final List<String> options;
  final String? selected;
  final ValueChanged<String> onSelected;
  final bool allowFree;
  final bool freeSelected;
  final VoidCallback? onFree;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 10,
    children: [
      for (final o in options)
        ChoiceChip(
          label: Text(o, style: const TextStyle(fontSize: 15)),
          selected: selected == o,
          onSelected: (_) => onSelected(o),
        ),
      if (allowFree)
        ChoiceChip(
          label: const Text('직접 입력', style: TextStyle(fontSize: 15)),
          selected: freeSelected,
          onSelected: (_) => onFree?.call(),
        ),
    ],
  );
}

/// 한 줄 키워드 입력. 자동 포커스, 플레이스홀더에 예시.
class TossKeywordField extends StatelessWidget {
  const TossKeywordField({
    super.key,
    required this.controller,
    this.placeholder,
    this.onSubmitted,
    this.onChanged,
    this.autofocus = true,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String? placeholder;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final bool autofocus;
  final int maxLines;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    autofocus: autofocus,
    maxLines: maxLines,
    minLines: 1,
    style: const TextStyle(fontSize: 18),
    textInputAction: maxLines == 1 ? TextInputAction.done : TextInputAction.newline,
    onChanged: onChanged,
    onSubmitted: (v) {
      final t = v.trim();
      if (t.isNotEmpty) onSubmitted?.call(t);
    },
    decoration: InputDecoration(hintText: placeholder ?? '한 단어로 적어 주세요'),
  );
}

/// 큰 버튼 하나 (파일 올리기 · 사진 찍기 · 글 붙여넣기).
class TossBigButton extends StatelessWidget {
  const TossBigButton({super.key, required this.label, required this.icon, required this.onPressed, this.filled = true});

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool filled;

  // Montage Button large: min-height 48, padding 13·20, body2 bold, radius 14.
  @override
  Widget build(BuildContext context) {
    final style = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size.fromHeight(48)),
      padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 20, vertical: 13)),
      shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
      textStyle: WidgetStatePropertyAll(MontageType.body2(MontageType.bold).copyWith(height: 1, fontFamily: 'Wanted Sans')),
    );
    final label = Text(this.label);
    final glyph = Icon(icon, size: 20);
    return filled
        ? FilledButton.icon(onPressed: onPressed, style: style, icon: glyph, label: label)
        : OutlinedButton.icon(onPressed: onPressed, style: style, icon: glyph, label: label);
  }
}
