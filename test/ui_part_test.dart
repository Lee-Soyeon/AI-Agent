import 'dart:convert';

import 'package:ai_agent/ui_parts/ui_part.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('chips 는 2~6개, 질문 필수', () {
    final ok = UiPart.fromJson({'type': 'chips', 'question': '어느 열?', 'options': ['품목', '단가']});
    expect(ok.type, UiPartType.chips);
    expect(ok.interactive, isTrue);
    expect(ok.options, ['품목', '단가']);

    final one = UiPart.fromJson({'type': 'chips', 'question': 'q', 'options': ['하나']});
    expect(one.type, UiPartType.textBlock);
    expect(one.fallbackReason, contains('2~6'));

    final seven = UiPart.fromJson({'type': 'chips', 'question': 'q', 'options': List.filled(7, 'x')});
    expect(seven.type, UiPartType.textBlock);

    final noQ = UiPart.fromJson({'type': 'chips', 'options': ['a', 'b']});
    expect(noQ.type, UiPartType.textBlock);
  });

  test('알 수 없는 type · 객체 아님 · JSON 아님 → text_block', () {
    expect(UiPart.fromJson({'type': 'html', 'html': '<b>x</b>'}).type, UiPartType.textBlock);
    expect(UiPart.fromJson('그냥 글').type, UiPartType.textBlock);
    expect(UiPart.fromJson('그냥 글').text, '그냥 글');
    final decoded = UiPart.decode('not json');
    expect(decoded.type, UiPartType.textBlock);
    expect(decoded.fallbackReason, 'JSON 이 아님');
  });

  test('table 은 20행까지만, 행은 배열', () {
    final p = UiPart.fromJson({
      'type': 'table',
      'headers': ['a', 'b'],
      'rows': [for (var i = 0; i < 30; i++) ['$i', 'x']],
    });
    expect(p.type, UiPartType.table);
    expect(p.rows.length, UiPart.tableRowsMax);
    expect(p.interactive, isFalse);
    expect(UiPart.fromJson({'type': 'table', 'headers': ['a'], 'rows': ['not-a-row']}).type, UiPartType.textBlock);
    expect(UiPart.fromJson({'type': 'table', 'headers': [], 'rows': []}).type, UiPartType.textBlock);
  });

  test('checklist 는 1~12개, done 길이 일치', () {
    expect(UiPart.fromJson({'type': 'checklist', 'items': ['a']}).type, UiPartType.checklist);
    expect(UiPart.fromJson({'type': 'checklist', 'items': List.filled(13, 'a')}).type, UiPartType.textBlock);
    expect(UiPart.fromJson({'type': 'checklist', 'items': ['a', 'b'], 'done': [true]}).type, UiPartType.textBlock);
    final ok = UiPart.fromJson({'type': 'checklist', 'items': ['a', 'b'], 'done': [true, false]});
    expect(ok.done, [true, false]);
  });

  test('text_block 은 2000자에서 자른다', () {
    final p = UiPart.fromJson({'type': 'text_block', 'text': 'x' * 5000});
    expect(p.text.length, UiPart.textMax + 1); // + 말줄임표
  });

  test('confirm · keyword · file_button · before_after 필수 필드', () {
    expect(UiPart.fromJson({'type': 'confirm', 'sentence': '엑셀 채워줘'}).sentence, '엑셀 채워줘');
    expect(UiPart.fromJson({'type': 'confirm'}).type, UiPartType.textBlock);
    expect(UiPart.fromJson({'type': 'keyword', 'question': '무엇을?', 'placeholder': '예'}).type, UiPartType.keyword);
    expect(UiPart.fromJson({'type': 'file_button', 'question': 'q', 'label': '올리기', 'accept': 'photo'}).accept, 'photo');
    expect(UiPart.fromJson({'type': 'file_button', 'question': 'q'}).type, UiPartType.textBlock);
    expect(UiPart.fromJson({'type': 'before_after', 'before': '전', 'after': '후'}).type, UiPartType.beforeAfter);
    expect(UiPart.fromJson({'type': 'before_after', 'before': '전'}).type, UiPartType.textBlock);
  });

  test('toJson 은 검증된 데이터를 그대로 돌려준다', () {
    final p = UiPart.fromJson({'type': 'chips', 'question': 'q', 'options': ['a', 'b'], 'allow_free': false});
    expect(p.allowFree, isFalse);
    expect(jsonDecode(jsonEncode(p.toJson()))['type'], 'chips');
  });
}
