import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:ai_agent/agent/agent_models.dart';
import 'package:ai_agent/ui/app_theme.dart';
import 'package:ai_agent/ui/browser_pip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<Uint8List> _png(WidgetTester tester) async {
  return (await tester.runAsync(() async {
    final rec = ui.PictureRecorder();
    Canvas(rec).drawRect(const Rect.fromLTWH(0, 0, 41, 90), Paint()..color = Colors.teal);
    final img = await rec.endRecording().toImage(41, 90);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  }))!;
}

Future<void> _pump(WidgetTester tester, Uint8List shot, {VoidCallback? onOpen}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(Brightness.light),
      home: Scaffold(
        body: Stack(
          children: [
            ListView(children: const [Text('로그')]),
            Positioned.fill(
              child: BrowserPip(
                screenshot: shot,
                live: true,
                caption: '담기 버튼 클릭',
                onOpen: onOpen ?? () {},
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

void main() {
  test('latestAction 은 가장 최근 동작 로그를 고른다', () {
    final logs = [
      AgentLogEntry(LogKind.action, '검색창에 입력'),
      AgentLogEntry(LogKind.thought, '생각'),
      AgentLogEntry(LogKind.action, '담기 버튼 클릭'),
      AgentLogEntry(LogKind.observation, '페이지'),
    ];
    expect(latestAction(logs), '담기 버튼 클릭');
    expect(latestAction([AgentLogEntry(LogKind.user, 'x')]), isNull);
  });

  testWidgets('미니 화면: 오른쪽 위에 뜨고, 탭하면 열기, 접었다 펼 수 있다', (tester) async {
    final shot = await _png(tester);
    var opened = 0;
    await _pump(tester, shot, onOpen: () => opened++);
    await tester.pump();

    expect(find.text('담기 버튼 클릭'), findsOneWidget);
    expect(find.text('LIVE'), findsOneWidget);
    final screen = tester.getSize(find.byType(Scaffold));
    final pip = tester.getRect(find.byType(Hero));
    expect(pip.right, greaterThan(screen.width - 40));
    expect(pip.top, lessThan(40));

    await tester.tap(find.byType(Hero));
    expect(opened, 1);

    await tester.tap(find.byIcon(Icons.remove));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(Hero), findsNothing);
    expect(find.byIcon(Icons.smartphone), findsOneWidget);

    await tester.tap(find.byIcon(Icons.smartphone));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(Hero), findsOneWidget);
  });

  testWidgets('끌어서 놓으면 가까운 모서리(왼쪽 아래)로 붙는다', (tester) async {
    final shot = await _png(tester);
    await _pump(tester, shot);
    await tester.pump();

    final screen = tester.getSize(find.byType(Scaffold));
    await tester.drag(find.byType(Hero), Offset(-screen.width * 0.7, screen.height * 0.7));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final pip = tester.getRect(find.byType(Hero));
    expect(pip.left, lessThan(20));
    expect(pip.bottom, greaterThan(screen.height - 20));
  });

  testWidgets('dimmed 면 반투명해진다', (tester) async {
    final shot = await _png(tester);
    Widget app(bool dimmed) => MaterialApp(
      theme: buildAppTheme(Brightness.light),
      home: Scaffold(
        body: BrowserPip(screenshot: shot, live: false, dimmed: dimmed, onOpen: () {}),
      ),
    );
    await tester.pumpWidget(app(false));
    double opacity() => tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity;
    expect(opacity(), 1);
    await tester.pumpWidget(app(true));
    expect(opacity(), lessThan(0.5));
  });
}
