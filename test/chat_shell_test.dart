import 'dart:io';

import 'package:ai_agent/agent/agent_controller.dart';
import 'package:ai_agent/agent/agent_models.dart';
import 'package:ai_agent/agent/chat_session.dart';
import 'package:ai_agent/browser/session_store.dart';
import 'package:ai_agent/core/settings_store.dart';
import 'package:ai_agent/google/google_auth.dart';
import 'package:ai_agent/google/writing_style.dart';
import 'package:ai_agent/openai/chatgpt_auth.dart';
import 'package:ai_agent/services/service_catalog.dart';
import 'package:ai_agent/ui/app_theme.dart';
import 'package:ai_agent/ui/main_shell.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('ChatSession 저장/복원', () {
    test('로그·결과·서버 작업 id 를 저장하고 detail 은 버린다', () {
      final s = ChatSession(id: 'a', title: '메일 요약', remoteTaskId: 't1', remoteLogCount: 3)
        ..status = AgentStatus.finished
        ..lastResult = '요약 결과'
        ..logs.addAll([
          AgentLogEntry(LogKind.user, '메일 요약해줘'),
          AgentLogEntry(LogKind.observation, '페이지', detail: '긴 스냅샷'),
        ]);
      final r = ChatSession.fromJson(s.toJson());
      expect(r.title, '메일 요약');
      expect(r.status, AgentStatus.finished);
      expect(r.lastResult, '요약 결과');
      expect(r.remoteTaskId, 't1');
      expect(r.remoteLogCount, 3);
      expect(r.logs.map((l) => l.text), ['메일 요약해줘', '페이지']);
      expect(r.logs[1].detail, isNull);
      expect(r.canContinue, isTrue);
    });

    test('이 폰에서 돌던 작업은 복원하면 취소됨으로, 이어서 지시는 불가', () {
      final s = ChatSession(id: 'b', status: AgentStatus.running)
        ..logs.add(AgentLogEntry(LogKind.user, 'x'));
      final r = ChatSession.fromJson(s.toJson());
      expect(r.status, AgentStatus.cancelled);
      expect(r.canContinue, isFalse);
      expect(r.isEmpty, isFalse);
    });

    test('제목은 40자로 자른다', () {
      expect(ChatSession.titleFrom('  a\n b  '), 'a b');
      expect(ChatSession.titleFrom('가' * 50), '${'가' * 40}…');
    });
  });

  testWidgets('하단 탭 4개로 홈·채팅·로그인·모델 화면을 오간다', (tester) async {
    SharedPreferences.setMockInitialValues({
      'chat_sessions': '[{"id":"1","title":"쿠팡 장바구니 확인","status":"finished","lastResult":"3개 담겨 있어요","logs":[]}]',
    });
    final chatgpt = ChatGptAuth();
    final settings = SettingsStore(chatgpt: chatgpt);
    final sessions = SiteSessionStore();
    final google = GoogleAuthService();
    final style = WritingStyleStore();
    final agent = AgentController(
      settings: settings,
      sessions: sessions,
      google: google,
      writingStyle: style,
      navigatorKey: GlobalKey<NavigatorState>(),
    );
    await agent.init();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: settings),
          ChangeNotifierProvider.value(value: sessions),
          ChangeNotifierProvider.value(value: google),
          ChangeNotifierProvider.value(value: chatgpt),
          ChangeNotifierProvider.value(value: style),
          ChangeNotifierProvider.value(value: agent),
          Provider.value(
            value: ServiceCatalog.fromJson(File(ServiceCatalog.assetPath).readAsStringSync()),
          ),
          ChangeNotifierProvider(create: (_) => ShellTabs()),
        ],
        child: MaterialApp(theme: buildAppTheme(Brightness.light), home: const MainShell()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('시작하기'), findsOneWidget);
    for (final t in AppTab.values) {
      expect(find.text(t.label), findsWidgets);
    }

    await tester.tap(find.text('채팅').last);
    await tester.pumpAndSettle();
    expect(find.text('쿠팡 장바구니 확인'), findsOneWidget);
    expect(find.text('3개 담겨 있어요'), findsOneWidget);

    await tester.tap(find.text('로그인').last);
    await tester.pumpAndSettle();
    expect(find.text('로그인 관리'), findsOneWidget);

    await tester.tap(find.text('모델').last);
    await tester.pumpAndSettle();
    expect(find.text('모델 설정'), findsOneWidget);
  });
}
