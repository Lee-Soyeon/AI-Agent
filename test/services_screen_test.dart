import 'dart:io';

import 'package:ai_agent/services/service_catalog.dart';
import 'package:ai_agent/ui/services_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('지원 서비스 화면: 목록·검색·필터·앱 전용 안내', (tester) async {
    final catalog = ServiceCatalog.fromJson(File(ServiceCatalog.assetPath).readAsStringSync());
    await tester.pumpWidget(
      Provider.value(
        value: catalog,
        child: const MaterialApp(home: ServicesScreen()),
      ),
    );
    expect(find.textContaining('지원 서비스 (${catalog.supported.length}/'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '배달');
    await tester.pump();
    expect(find.text('배달의민족'), findsOneWidget);
    expect(find.text('쿠팡'), findsNothing);

    await tester.tap(find.text('배달의민족'));
    await tester.pumpAndSettle();
    expect(find.textContaining('브라우저로는 지원하지 않습니다'), findsOneWidget);
    await tester.tap(find.text('확인'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(find.text('배달의민족'), findsNothing); // 앱 전용은 숨김
    expect(find.text('요기요'), findsOneWidget); // 일부 지원은 표시
  });
}
