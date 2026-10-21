import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../agent/intake_content.dart';
import 'toss_form.dart';

/// 사진 · 파일 · 글을 받아 [IntakeContent] 로 만든다 (웹·앱 공용).
/// accept: photo | file | text. 취소하면 null.
Future<IntakeContent?> pickIntakeContent(BuildContext context, String accept) async {
  switch (accept) {
    case 'photo':
      final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600, imageQuality: 85);
      if (x == null) return null;
      final bytes = await x.readAsBytes();
      final name = x.name.isEmpty ? 'photo.jpg' : x.name;
      final mime = name.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg';
      return IntakeContent.photo(bytes, name: name, mime: mime);
    case 'text':
      if (!context.mounted) return null;
      return _pasteSheet(context);
    default:
      final f = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['xlsx', 'xlsm', 'csv', 'txt', 'md'],
      );
      if (f == null) return null;
      final bytes = await f.readAsBytes();
      try {
        return IntakeContent.file(bytes, name: f.name);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('파일을 읽지 못했어요: $e')));
        }
        return null;
      }
  }
}

Future<IntakeContent?> _pasteSheet(BuildContext context) {
  final c = TextEditingController();
  return showModalBottomSheet<IntakeContent>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 16 + MediaQuery.viewInsetsOf(ctx).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('글을 붙여 넣어 주세요', style: Theme.of(ctx).textTheme.titleLarge),
          const SizedBox(height: 12),
          TossKeywordField(controller: c, placeholder: '여기에 길게 눌러 붙여넣기', maxLines: 8),
          const SizedBox(height: 12),
          SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: () {
                final t = c.text.trim();
                if (t.isEmpty) return;
                Navigator.pop(ctx, IntakeContent.text(t));
              },
              child: const Text('다음'),
            ),
          ),
        ],
      ),
    ),
  );
}
