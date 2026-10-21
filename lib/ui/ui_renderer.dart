import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ui_parts/ui_part.dart';
import 'app_theme.dart';

/// show_ui 부품 8종을 토스 입력 폼 문법으로 그린다.
///
/// 큰 질문 한 줄 · 흐린 "왜 묻는지" 한 줄 · 칩 또는 한 줄 입력 · 큰 버튼 하나.
/// 사용자의 답은 [onAnswer] 로 돌려준다 (interactive 부품만).
/// 파일 버튼은 [onPickFile] 이 있으면 그것을 부르고, 없으면 onAnswer('(파일 선택)') 한다.
class UiPartView extends StatefulWidget {
  const UiPartView({
    super.key,
    required this.part,
    this.onAnswer,
    this.onPickFile,
    this.compact = false,
  });

  final UiPart part;
  final ValueChanged<String>? onAnswer;
  final Future<void> Function(String accept)? onPickFile;

  /// 로그 안에 작게 넣을 때 (제목 크기 축소).
  final bool compact;

  @override
  State<UiPartView> createState() => _UiPartViewState();
}

class _UiPartViewState extends State<UiPartView> {
  final _field = TextEditingController();
  bool _free = false;
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    if (widget.part.type == UiPartType.confirm) _field.text = widget.part.sentence;
  }

  @override
  void didUpdateWidget(covariant UiPartView old) {
    super.didUpdateWidget(old);
    if (old.part != widget.part) {
      _free = false;
      _editing = false;
      _field.text = widget.part.type == UiPartType.confirm ? widget.part.sentence : '';
    }
  }

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _submit() {
    final t = _field.text.trim();
    if (t.isEmpty) return;
    widget.onAnswer?.call(t);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.part;
    return switch (p.type) {
      UiPartType.chips => _chips(context, p),
      UiPartType.keyword => _keyword(context, p),
      UiPartType.fileButton => _fileButton(context, p),
      UiPartType.confirm => _confirm(context, p),
      UiPartType.table => _table(context, p),
      UiPartType.beforeAfter => _beforeAfter(context, p),
      UiPartType.checklist => _checklist(context, p),
      UiPartType.textBlock => _textBlock(context, p),
    };
  }

  // ---- 공통 조각 ----

  Widget _question(BuildContext context, String? q, String? why) {
    final t = AppTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (q != null)
          Text(
            q,
            style: TextStyle(
              fontSize: widget.compact ? 17 : 22,
              fontWeight: FontWeight.w700,
              height: 1.35,
              letterSpacing: -0.4,
              color: t.ink,
            ),
          ),
        if (why != null && why.trim().isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(why, style: TextStyle(color: t.muted, fontSize: 14, height: 1.4)),
        ],
      ],
    );
  }

  Widget _caption(BuildContext context, String? c) => c == null || c.trim().isEmpty
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(c, style: TextStyle(color: AppTokens.of(context).muted, fontSize: 13.5)),
        );

  Widget _chipWrap(List<String> options, {bool withFree = false}) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final o in options)
        ChoiceChip(
          label: Text(o),
          selected: false,
          onSelected: (_) => widget.onAnswer?.call(o),
        ),
      if (withFree)
        ChoiceChip(
          label: const Text('직접 입력'),
          selected: _free,
          onSelected: (_) => setState(() => _free = true),
        ),
    ],
  );

  Widget _freeField(BuildContext context, String? placeholder) => Row(
    children: [
      Expanded(
        child: TextField(
          controller: _field,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(hintText: placeholder ?? '한 단어로 적어 주세요', isDense: true),
        ),
      ),
      const SizedBox(width: 8),
      FilledButton(onPressed: _submit, child: const Text('다음')),
    ],
  );

  // ---- 부품 ----

  Widget _chips(BuildContext context, UiPart p) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _question(context, p.question, p.why),
      const SizedBox(height: 14),
      _chipWrap(p.options, withFree: p.allowFree),
      if (_free) ...[const SizedBox(height: 12), _freeField(context, p.placeholder)],
    ],
  );

  Widget _keyword(BuildContext context, UiPart p) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _question(context, p.question, p.why),
      const SizedBox(height: 14),
      if (p.options.isNotEmpty) ...[_chipWrap(p.options), const SizedBox(height: 12)],
      _freeField(context, p.placeholder),
    ],
  );

  Widget _fileButton(BuildContext context, UiPart p) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _question(context, p.question, p.why),
      const SizedBox(height: 14),
      SizedBox(
        height: 56,
        child: FilledButton.icon(
          icon: Icon(switch (p.accept) {
            'photo' => Icons.photo_camera_outlined,
            'text' => Icons.content_paste,
            _ => Icons.upload_file_outlined,
          }),
          label: Text(p.label, style: const TextStyle(fontSize: 16)),
          onPressed: () async {
            if (widget.onPickFile != null) {
              await widget.onPickFile!(p.accept);
            } else {
              widget.onAnswer?.call('(파일 선택)');
            }
          },
        ),
      ),
    ],
  );

  Widget _confirm(BuildContext context, UiPart p) {
    final t = AppTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _question(context, p.title, null),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: t.tint,
            borderRadius: BorderRadius.circular(AppTokens.rSm),
            border: Border.all(color: t.lineStrong),
          ),
          child: _editing
              ? TextField(
                  controller: _field,
                  autofocus: true,
                  minLines: 2,
                  maxLines: 8,
                  decoration: const InputDecoration.collapsed(hintText: '시킬 문장'),
                )
              : SelectableText(_field.text, style: TextStyle(fontSize: 16, height: 1.55, color: t.ink)),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 52,
                child: FilledButton(onPressed: _submit, child: const Text('실행', style: TextStyle(fontSize: 16))),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: () => setState(() => _editing = !_editing),
              child: Text(_editing ? '완료' : '고치기'),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: _field.text));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('복사했어요')));
                }
              },
              child: const Text('복사'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _table(BuildContext context, UiPart p) {
    final t = AppTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _caption(context, p.caption),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowHeight: 40,
            dataRowMinHeight: 36,
            dataRowMaxHeight: 56,
            columnSpacing: 20,
            headingTextStyle: TextStyle(fontWeight: FontWeight.w700, color: t.ink, fontSize: 13.5),
            dataTextStyle: TextStyle(color: t.ink, fontSize: 13.5),
            columns: [for (final h in p.headers) DataColumn(label: Text(h))],
            rows: [
              for (final r in p.rows)
                DataRow(
                  cells: [
                    for (var i = 0; i < p.headers.length; i++) DataCell(Text(i < r.length ? r[i] : '')),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _beforeAfter(BuildContext context, UiPart p) {
    final t = AppTokens.of(context);
    Widget card(String label, String body) => Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: t.tint,
          borderRadius: BorderRadius.circular(AppTokens.rSm),
          border: Border.all(color: t.lineStrong),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: t.muted, fontSize: 12, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            if (body.startsWith('http') || body.startsWith('data:image'))
              Image.network(body, errorBuilder: (_, _, _) => Text(body, style: const TextStyle(fontSize: 12)))
            else
              SelectableText(body, style: TextStyle(color: t.ink, fontSize: 14, height: 1.5)),
          ],
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _caption(context, p.caption),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [card('전', p.before), const SizedBox(width: 8), card('후', p.after)],
        ),
      ],
    );
  }

  Widget _checklist(BuildContext context, UiPart p) {
    final t = AppTokens.of(context);
    final done = p.done;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _caption(context, p.caption),
        for (var i = 0; i < p.items.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  i < done.length && done[i] ? Icons.check_circle : Icons.radio_button_unchecked,
                  size: 20,
                  color: i < done.length && done[i] ? t.accent : t.muted,
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(p.items[i], style: TextStyle(color: t.ink, fontSize: 15, height: 1.45))),
              ],
            ),
          ),
      ],
    );
  }

  Widget _textBlock(BuildContext context, UiPart p) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _caption(context, p.caption),
      SelectableText(p.text, style: TextStyle(color: AppTokens.of(context).ink, fontSize: 15, height: 1.55)),
    ],
  );
}
