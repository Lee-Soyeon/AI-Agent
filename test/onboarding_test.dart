import 'dart:io';

import 'package:ai_agent/core/settings_store.dart';
import 'package:ai_agent/openai/chatgpt_auth.dart';
import 'package:ai_agent/recipes/recipe_catalog.dart';
import 'package:ai_agent/ui/app_theme.dart';
import 'package:ai_agent/ui/onboarding_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('3문답: 칩을 누르면 다음 화면, 마지막에 프로필이 저장된다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsStore(chatgpt: ChatGptAuth(store: MemoryChatGptTokenStore()));
    final catalog = RecipeCatalog.fromJson(File('server/app/tasks.json').readAsStringSync());
    var done = false;
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: settings),
          Provider<RecipeCatalog?>.value(value: catalog),
        ],
        child: MaterialApp(
          theme: buildAppTheme(Brightness.light),
          home: OnboardingScreen(onDone: () => done = true),
        ),
      ),
    );
    expect(find.text('주로 어떤 일을 하세요?'), findsOneWidget);
    expect(find.text('건너뛰기'), findsOneWidget);
    await tester.tap(find.text('아르바이트'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('요즘 반복해서 하는 일이 있나요?'), findsOneWidget);
    expect(find.text('엑셀 정리'), findsOneWidget); // routines[parttime]
    await tester.tap(find.text('엑셀 정리'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('주로 폰이에요, 컴퓨터예요?'), findsOneWidget);
    await tester.tap(find.text('폰'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(done, isTrue);
    expect(settings.persona, 'parttime');
    expect(settings.routine, '엑셀 정리');
    expect(settings.device, 'phone');
    expect(settings.onboardingDone, isTrue);
    expect(settings.profileSummary, contains('반복하는 일: 엑셀 정리'));
  });

  testWidgets('건너뛰기도 온보딩 완료로 저장한다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsStore(chatgpt: ChatGptAuth(store: MemoryChatGptTokenStore()));
    var done = false;
    await tester.pumpWidget(
      MultiProvider(
        providers: [ChangeNotifierProvider.value(value: settings), Provider<RecipeCatalog?>.value(value: null)],
        child: MaterialApp(home: OnboardingScreen(onDone: () => done = true)),
      ),
    );
    await tester.tap(find.text('건너뛰기'));
    await tester.pumpAndSettle();
    expect(done, isTrue);
    expect(settings.onboardingDone, isTrue);
    expect(settings.profileSummary, isNull);
  });
}
