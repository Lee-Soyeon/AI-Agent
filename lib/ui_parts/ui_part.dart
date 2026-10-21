import 'dart:convert';

/// show_ui 부품 (server/app/ui_schema.json). LLM 이 보낸 JSON 을 검증해서 담는다.
///
/// 검증에 실패하면 예외를 던지지 않고 [UiPart.fallback] 으로 text_block 을 만든다.
/// 상한은 서버 ui_schema.py 와 같다: 칩 2~6, 표 20행, 체크리스트 12개, 글 2000자.
enum UiPartType {
  chips(interactive: true),
  keyword(interactive: true),
  fileButton(interactive: true, wire: 'file_button'),
  confirm(interactive: true),
  table(interactive: false),
  beforeAfter(interactive: false, wire: 'before_after'),
  checklist(interactive: false),
  textBlock(interactive: false, wire: 'text_block');

  const UiPartType({required this.interactive, String? wire}) : _wire = wire; // ignore: prefer_initializing_formals

  /// 사용자의 답을 기다리는 부품인지.
  final bool interactive;
  final String? _wire;

  /// JSON 의 "type" 값.
  String get wire => _wire ?? name;

  static UiPartType? parse(Object? v) {
    for (final t in values) {
      if (t.wire == v) return t;
    }
    return null;
  }
}

class UiPart {
  UiPart._(this.type, this.data);

  /// 검증을 통과한 부품만 만든다. 실패하면 text_block 으로 떨어뜨린다.
  factory UiPart.fromJson(Object? json) {
    final r = validate(json);
    if (r.ok) return UiPart._(r.type!, r.data!);
    final text = json is String ? json : jsonEncode(json);
    return UiPart.fallback(text, reason: r.error);
  }

  /// 문자열(로그 detail 등)에서 만든다.
  factory UiPart.decode(String source) {
    try {
      return UiPart.fromJson(jsonDecode(source));
    } catch (_) {
      return UiPart.fallback(source, reason: 'JSON 이 아님');
    }
  }

  factory UiPart.fallback(String text, {String? reason}) => UiPart._(UiPartType.textBlock, {
    'type': 'text_block',
    'text': _clip(text, textMax),
    'fallback_reason': ?reason,
  });

  final UiPartType type;
  final Map<String, dynamic> data;

  static const chipsMin = 2;
  static const chipsMax = 6;
  static const tableRowsMax = 20;
  static const checklistMax = 12;
  static const textMax = 2000;

  bool get interactive => type.interactive;
  String? get question => data['question'] as String?;
  String? get why => data['why'] as String?;
  String? get placeholder => data['placeholder'] as String?;
  String? get caption => data['caption'] as String?;
  bool get allowFree => data['allow_free'] != false;
  List<String> get options => _strings(data['options']);
  String get label => data['label'] as String? ?? '올리기';
  String get accept => data['accept'] as String? ?? 'file';
  String get sentence => data['sentence'] as String? ?? '';
  String get title => data['title'] as String? ?? '이렇게 시킬까요?';
  List<String> get headers => _strings(data['headers']);
  List<List<String>> get rows => [
    for (final r in (data['rows'] as List? ?? const [])) _strings(r),
  ];
  String get before => '${data['before'] ?? ''}';
  String get after => '${data['after'] ?? ''}';
  List<String> get items => _strings(data['items']);
  List<bool> get done => [for (final d in (data['done'] as List? ?? const [])) d == true];
  String get text => data['text'] as String? ?? '';
  String? get fallbackReason => data['fallback_reason'] as String?;

  Map<String, dynamic> toJson() => data;

  static List<String> _strings(Object? v) => v is List ? [for (final e in v) '$e'] : const [];

  static String _clip(String s, int max) => s.length > max ? '${s.substring(0, max)}…' : s;

  /// 부품 하나를 검증한다. 실패 이유를 돌려준다.
  static UiValidation validate(Object? json) {
    if (json is! Map) return const UiValidation.fail('객체가 아님');
    final m = json.cast<String, dynamic>();
    final type = UiPartType.parse(m['type']);
    if (type == null) return UiValidation.fail('알 수 없는 type: ${m['type']}');
    String? str(String k) => m[k] is String && (m[k] as String).trim().isNotEmpty ? m[k] as String : null;
    List<String>? strList(String k) {
      final v = m[k];
      if (v is! List) return null;
      final out = [for (final e in v) '$e'.trim()];
      return out.any((e) => e.isEmpty) ? null : out;
    }

    switch (type) {
      case UiPartType.chips:
        if (str('question') == null) return const UiValidation.fail('chips: question 없음');
        final opts = strList('options');
        if (opts == null || opts.length < chipsMin || opts.length > chipsMax) {
          return UiValidation.fail('chips: options 는 $chipsMin~$chipsMax개');
        }
      case UiPartType.keyword:
        if (str('question') == null) return const UiValidation.fail('keyword: question 없음');
        if (m['options'] != null && strList('options') == null) return const UiValidation.fail('keyword: options 형식');
      case UiPartType.fileButton:
        if (str('question') == null || str('label') == null) return const UiValidation.fail('file_button: question/label 없음');
      case UiPartType.confirm:
        if (str('sentence') == null) return const UiValidation.fail('confirm: sentence 없음');
      case UiPartType.table:
        final headers = strList('headers');
        if (headers == null || headers.isEmpty) return const UiValidation.fail('table: headers 없음');
        final rows = m['rows'];
        if (rows is! List) return const UiValidation.fail('table: rows 없음');
        final clipped = rows.take(tableRowsMax).toList();
        for (final r in clipped) {
          if (r is! List) return const UiValidation.fail('table: 행이 배열이 아님');
        }
        m['rows'] = [for (final r in clipped) [for (final c in r as List) '$c']];
      case UiPartType.beforeAfter:
        if (m['before'] == null || m['after'] == null) return const UiValidation.fail('before_after: before/after 없음');
      case UiPartType.checklist:
        final items = strList('items');
        if (items == null || items.isEmpty || items.length > checklistMax) {
          return UiValidation.fail('checklist: items 는 1~$checklistMax개');
        }
        if (m['done'] != null && (m['done'] is! List || (m['done'] as List).length != items.length)) {
          return const UiValidation.fail('checklist: done 길이가 다름');
        }
      case UiPartType.textBlock:
        final t = m['text'];
        if (t is! String) return const UiValidation.fail('text_block: text 없음');
        m['text'] = _clip(t, textMax);
    }
    return UiValidation.ok(type, m);
  }
}

class UiValidation {
  const UiValidation.ok(this.type, this.data) : error = null;
  const UiValidation.fail(this.error) : type = null, data = null;

  final UiPartType? type;
  final Map<String, dynamic>? data;
  final String? error;

  bool get ok => error == null;
}
