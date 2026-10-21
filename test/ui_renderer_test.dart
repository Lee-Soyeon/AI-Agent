import 'package:ai_agent/ui/app_theme.dart';
import 'package:ai_agent/ui/ui_renderer.dart';
import 'package:ai_agent/ui_parts/ui_part.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget wrap(Widget child) => MaterialApp(
  theme: buildAppTheme(Brightness.light),
  home: Scaffold(body: SingleChildScrollView(child: Padding(padding: const EdgeInsets.all(16), child: child))),
);

void main() {
  testWidgets('chips 를 누르면 답이 돌아온다 · 직접 입력 칩이 붙는다', (tester) async {
    String? answer;
    final part = UiPart.fromJson({'type': 'chips', 'question': '어느 열?', 'why': '머리글', 'options': ['품목', '단가']});
    await tester.pumpWidget(wrap(UiPartView(part: part, onAnswer: (v) => answer = v)));
    expect(find.text('어느 열?'), findsOneWidget);
    expect(find.text('머리글'), findsOneWidget);
    expect(find.text('직접 입력'), findsOneWidget);
    await tester.tap(find.text('단가'));
    await tester.pump();
    expect(answer, '단가');

    await tester.tap(find.text('직접 입력'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '카테고리');
    await tester.tap(find.text('다음'));
    await tester.pump();
    expect(answer, '카테고리');
  });

  testWidgets('confirm 의 실행은 문장을 돌려주고, 고치기는 편집 가능', (tester) async {
    String? answer;
    final part = UiPart.fromJson({'type': 'confirm', 'sentence': '엑셀 채워줘'});
    await tester.pumpWidget(wrap(UiPartView(part: part, onAnswer: (v) => answer = v)));
    expect(find.text('이렇게 시킬까요?'), findsOneWidget);
    expect(find.text('엑셀 채워줘'), findsOneWidget);
    await tester.tap(find.text('고치기'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '엑셀 채워줘. 빈 칸은 비워 둬');
    await tester.tap(find.text('실행'));
    await tester.pump();
    expect(answer, '엑셀 채워줘. 빈 칸은 비워 둬');
  });

  testWidgets('table 은 머리글과 행을 그린다', (tester) async {
    final part = UiPart.fromJson({
      'type': 'table',
      'caption': '채운 결과',
      'headers': ['품목', '카테고리'],
      'rows': [['사과', '식품'], ['세제', '생활']],
    });
    await tester.pumpWidget(wrap(UiPartView(part: part)));
    expect(find.text('채운 결과'), findsOneWidget);
    expect(find.text('품목'), findsOneWidget);
    expect(find.text('세제'), findsOneWidget);
    expect(find.byType(DataTable), findsOneWidget);
  });

  testWidgets('checklist · before_after · text_block 폴백', (tester) async {
    await tester.pumpWidget(
      wrap(
        Column(
          children: [
            UiPartView(part: UiPart.fromJson({'type': 'checklist', 'items': ['마감 10/31', '우대 영어'], 'done': [true, false]})),
            UiPartView(part: UiPart.fromJson({'type': 'before_after', 'before': '초안', 'after': '다듬음'})),
            UiPartView(part: UiPart.fromJson({'type': 'html', 'x': 1})),
          ],
        ),
      ),
    );
    expect(find.text('마감 10/31'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    expect(find.text('초안'), findsOneWidget);
    expect(find.text('다듬음'), findsOneWidget);
    expect(find.textContaining('"type":"html"'), findsOneWidget); // 폴백은 원문 JSON 을 글로
  });

  testWidgets('file_button 은 onPickFile 을 accept 와 함께 부른다', (tester) async {
    String? picked;
    final part = UiPart.fromJson({'type': 'file_button', 'question': '사진을', 'label': '사진 찍기', 'accept': 'photo'});
    await tester.pumpWidget(wrap(UiPartView(part: part, onPickFile: (a) async => picked = a)));
    await tester.tap(find.text('사진 찍기'));
    await tester.pump();
    expect(picked, 'photo');
  });
}
