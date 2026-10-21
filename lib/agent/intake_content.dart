import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart';

/// 홈 "내 것부터 넣기" 로 받은 내용 (사진 · 파일 · 글). (PRD 4.3)
///
/// 엑셀은 머리글과 앞 20행을 텍스트 표로, 사진은 base64, 글은 그대로 담는다.
class IntakeContent {
  IntakeContent._({
    required this.kind,
    required this.name,
    this.text,
    this.headers = const [],
    this.imageBase64,
    this.mime,
  });

  /// photo | file | text
  final String kind;
  final String name;
  final String? text;
  final List<String> headers;
  final String? imageBase64;
  final String? mime;

  static const maxRows = 20;
  static const maxChars = 6000;

  factory IntakeContent.text(String text, {String name = '붙여 넣은 글'}) =>
      IntakeContent._(kind: 'text', name: name, text: _clip(text.trim()));

  factory IntakeContent.photo(Uint8List bytes, {required String name, String mime = 'image/jpeg'}) =>
      IntakeContent._(kind: 'photo', name: name, imageBase64: base64Encode(bytes), mime: mime);

  /// 파일 이름으로 xlsx / csv / 그 외 텍스트를 가른다.
  factory IntakeContent.file(Uint8List bytes, {required String name}) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.xlsx') || lower.endsWith('.xlsm')) return IntakeContent.xlsx(bytes, name: name);
    if (lower.endsWith('.csv')) return IntakeContent.csv(utf8.decode(bytes, allowMalformed: true), name: name);
    return IntakeContent._(kind: 'file', name: name, text: _clip(utf8.decode(bytes, allowMalformed: true).trim()));
  }

  factory IntakeContent.xlsx(Uint8List bytes, {required String name}) {
    final book = Excel.decodeBytes(bytes);
    for (final sheet in book.tables.values) {
      if (sheet.rows.isEmpty) continue;
      final rows = [
        for (final r in sheet.rows) [for (final c in r) (c?.value?.toString() ?? '').trim()],
      ];
      return IntakeContent.table(rows, name: name, sheet: sheet.sheetName);
    }
    return IntakeContent._(kind: 'file', name: name, text: '(빈 엑셀)');
  }

  factory IntakeContent.csv(String source, {required String name}) {
    final rows = [
      for (final line in const LineSplitter().convert(source))
        if (line.trim().isNotEmpty) [for (final c in line.split(',')) c.trim()],
    ];
    return IntakeContent.table(rows, name: name);
  }

  /// 표(행 목록)를 텍스트 표로. 첫 행이 머리글.
  factory IntakeContent.table(List<List<String>> rows, {required String name, String? sheet}) {
    final nonEmpty = rows.where((r) => r.any((c) => c.isNotEmpty)).toList();
    final headers = nonEmpty.isEmpty ? <String>[] : nonEmpty.first.where((h) => h.isNotEmpty).toList();
    final b = StringBuffer();
    if (sheet != null) b.writeln('시트: $sheet');
    b.writeln('전체 ${nonEmpty.length}행 (앞 $maxRows행만 표시)');
    for (final r in nonEmpty.take(maxRows + 1)) {
      b.writeln(r.join(' | '));
    }
    return IntakeContent._(kind: 'file', name: name, text: _clip(b.toString().trim()), headers: headers);
  }

  static String _clip(String s) => s.length > maxChars ? '${s.substring(0, maxChars)}\n…(생략)' : s;

  /// 프롬프트에 넣을 글. 사진은 서버가 비전으로 받으므로 이름만.
  String asPromptText() => switch (kind) {
    'photo' => '(첨부 사진: $name)',
    _ => text ?? '',
  };

  /// 서버 POST /intake 본문.
  Map<String, dynamic> toIntakeJson() => {
    'kind': kind,
    'name': name,
    if (text != null) 'text': text,
    if (imageBase64 != null) 'image_base64': imageBase64,
    if (mime != null) 'mime': mime,
  };
}
