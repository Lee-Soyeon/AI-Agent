import 'dart:typed_data';

import 'package:ai_agent/agent/intake_content.dart';
import 'package:ai_agent/agent/task_intake.dart';
import 'package:ai_agent/recipes/recipe_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

Recipe excel() => Recipe({
  'id': 'excel_fill',
  'title': '엑셀 빈 열 채우기',
  'prompt_template': "'{column}' 열을 채워줘. 값은 {values} 중 하나. 파일 내용: {file}",
  'steps': [
    {'id': 'file', 'kind': 'file', 'text': '엑셀을 올려주세요', 'button': '엑셀 올리기'},
    {'id': 'column', 'kind': 'chips', 'text': '어느 열?', 'options_from': 'file.headers', 'allow_free': true},
    {'id': 'values', 'kind': 'keyword', 'text': '값의 종류는?', 'options': ['파일에 있는 것 그대로']},
  ],
});

void main() {
  test('단계를 순서대로 답하면 문장이 조립된다', () {
    final i = TaskIntake(excel());
    expect(i.total, 3);
    expect(i.step!.id, 'file');
    expect(i.assembled, contains('…'));

    final csv = IntakeContent.csv('품목,카테고리,단가\n사과,,1000\n세제,,5000', name: 'a.csv');
    i.answerContent(csv);
    expect(i.step!.id, 'column');
    expect(i.optionsFor(i.step!), ['품목', '카테고리', '단가']); // options_from file.headers
    i.answer('카테고리');
    expect(i.step!.id, 'values');
    expect(i.assembled, startsWith("'카테고리' 열을 채워줘. 값은 …"));
    i.answer('식품·생활·전자');
    expect(i.isDone, isTrue);
    expect(i.sentence, startsWith("'카테고리' 열을 채워줘. 값은 식품·생활·전자 중 하나. 파일 내용: 전체 3행"));
    expect(i.sentence, contains('사과 |  | 1000'));
  });

  test('홈에서 내용을 넣고 오면 첫 내용 단계를 건너뛴다', () {
    final csv = IntakeContent.csv('이름,연락처\n김,010', name: 'b.csv');
    final i = TaskIntake(excel(), content: csv);
    expect(i.total, 2);
    expect(i.step!.id, 'column');
    expect(i.optionsFor(i.step!), ['이름', '연락처']);
    expect(i.back(), isFalse); // 건너뛴 단계로는 못 돌아간다
    i.answer('연락처');
    expect(i.position, 1);
    expect(i.back(), isTrue);
    expect(i.step!.id, 'column');
    expect(i.answers.containsKey('column'), isFalse);
  });

  test('options_from 인데 머리글이 없으면 기본 칩', () {
    final i = TaskIntake(excel(), content: IntakeContent.text('그냥 글'));
    // text 는 file 단계의 내용으로 들어간다 (첫 내용 단계 건너뜀)
    expect(i.step!.id, 'column');
    expect(i.optionsFor(i.step!), ['직접 고를게요']);
  });

  test('즉석 레시피는 단계가 없고 {content} 가 바로 들어간다', () {
    final r = Recipe.synthetic(title: '요약', promptTemplate: '요약: 첨부 내용으로 해줘. 내용: {content}');
    final i = TaskIntake(r, content: IntakeContent.text('긴 글'));
    expect(i.isDone, isTrue);
    expect(i.sentence, '요약: 첨부 내용으로 해줘. 내용: 긴 글');
    expect(r.isSynthetic, isTrue);
  });

  test('사진은 프롬프트에 이름만 들어가고 서버 본문에는 base64 가 들어간다', () {
    final c = IntakeContent.photo(Uint8List.fromList([1, 2, 3]), name: 'receipt.jpg');
    expect(c.asPromptText(), '(첨부 사진: receipt.jpg)');
    expect(c.toIntakeJson()['image_base64'], 'AQID');
    expect(c.toIntakeJson()['kind'], 'photo');
  });

  test('단계 4개는 생성 시점에 막힌다', () {
    expect(
      () => Recipe({
        'id': 'x',
        'title': 'x',
        'prompt_template': 'x',
        'steps': [for (var i = 0; i < 4; i++) {'id': 's$i', 'kind': 'keyword', 'text': 'q'}],
      }),
      throwsA(isA<AssertionError>()),
    );
  });
}
