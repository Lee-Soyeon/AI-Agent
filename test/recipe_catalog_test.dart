import 'dart:io';

import 'package:ai_agent/recipes/recipe_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = File('server/app/tasks.json').readAsStringSync();

  test('카탈로그를 읽고 모든 레시피가 단계 3개 이하', () {
    final c = RecipeCatalog.fromJson(source);
    expect(c.recipes.length, greaterThanOrEqualTo(9));
    for (final r in c.recipes) {
      expect(r.steps.length, lessThanOrEqualTo(Recipe.maxSteps), reason: r.id);
      expect(r.promptTemplate, isNotEmpty, reason: r.id);
      expect(r.title, isNotEmpty);
      for (final s in r.steps) {
        expect(['file', 'photo', 'text', 'chips', 'keyword'], contains(s.kind), reason: '${r.id}.${s.id}');
        if (s.kind == 'chips' && s.optionsFrom == null) {
          expect(s.options.length, inInclusiveRange(2, 6), reason: '${r.id}.${s.id}');
        }
      }
    }
  });

  test('페르소나 · 반복 일 · intake 기본 칩', () {
    final c = RecipeCatalog.fromJson(source);
    expect(c.personas.map((p) => p.id), containsAll(['home', 'parttime', 'jobseeker']));
    expect(c.routinesFor('parttime'), contains('엑셀 정리'));
    expect(c.routinesFor('없는값'), isNotEmpty);
    expect(c.intakeDefaults('photo').length, 3);
    expect(c.intakeDefaults('file').length, 3);
  });

  test('forPersona 는 내 것이 앞, 나머지는 뒤에 전부', () {
    final c = RecipeCatalog.fromJson(source);
    final list = c.forPersona('home');
    expect(list.length, c.recipes.length);
    final firstOther = list.indexWhere((r) => !r.personas.contains('home'));
    final lastMine = list.lastIndexWhere((r) => r.personas.contains('home'));
    expect(lastMine, lessThan(firstOther));
  });

  test('find · byId · todays · next 참조가 존재', () {
    final c = RecipeCatalog.fromJson(source);
    expect(c.find('엑셀 빈 열 채우기')?.id, 'excel_fill');
    expect(c.find('없는 제목'), isNull);
    expect(c.todays(DateTime(2026, 1, 1))?.id, c.recipes.first.id);
    for (final r in c.recipes) {
      if (r.next != null) expect(c.byId(r.next!), isNotNull, reason: '${r.id}.next');
    }
  });

  test('단계 4개짜리 레시피는 거부한다', () {
    expect(
      () => RecipeCatalog.fromJson('''{"recipes":[{"id":"x","title":"x","prompt_template":"{a}","steps":[
        {"id":"a","kind":"keyword","text":"a"},{"id":"b","kind":"keyword","text":"b"},
        {"id":"c","kind":"keyword","text":"c"},{"id":"d","kind":"keyword","text":"d"}]}]}'''),
      throwsA(anyOf(isA<StateError>(), isA<AssertionError>())),
    );
  });
}
