import 'package:ai_agent/agent/agent_controller.dart';
import 'package:ai_agent/agent/agent_models.dart';
import 'package:ai_agent/agent/chat_session.dart';
import 'package:ai_agent/browser/session_store.dart';
import 'package:ai_agent/core/settings_store.dart';
import 'package:ai_agent/google/google_auth.dart';
import 'package:ai_agent/google/writing_style.dart';
import 'package:ai_agent/openai/chatgpt_auth.dart';
import 'package:ai_agent/ui/history_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  late ChatSessionStore history;
  late AgentController agent;

  ChatSession chat(String title, String result) => ChatSession.create(title, vendor: 'anthropic')
    ..status = AgentStatus.finished
    ..lastResult = result
    ..logs.addAll([AgentLogEntry(LogKind.user, title), AgentLogEntry(LogKind.result, result)]);

  Widget app() => MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: history),
      ChangeNotifierProvider.value(value: agent),
    ],
    child: MaterialApp(navigatorKey: agent.navigatorKey, home: const HistoryScreen()),
  );

  setUp(() {
    history = ChatSessionStore.memory();
    agent = AgentController(
      settings: SettingsStore(chatgpt: ChatGptAuth(store: MemoryChatGptTokenStore())),
      sessions: SiteSessionStore(),
      google: GoogleAuthService(),
      writingStyle: WritingStyleStore(store: MemoryStyleProfileStore()),
      navigatorKey: GlobalKey<NavigatorState>(),
      history: history,
    );
  });

  testWidgets('지난 대화를 목록에서 열면 기록이 보이고 이어서 지시할 수 있다', (tester) async {
    history
      ..add(chat('Gmail 요약해줘', '메일 3통 요약'))
      ..add(chat('쿠팡 장바구니 보여줘', '생수 1개'));
    await tester.pumpWidget(app());

    expect(find.text('Gmail 요약해줘'), findsOneWidget);
    expect(find.text('쿠팡 장바구니 보여줘'), findsOneWidget);

    await tester.tap(find.text('Gmail 요약해줘'));
    await tester.pumpAndSettle();

    expect(agent.current?.title, 'Gmail 요약해줘');
    expect(find.text('메일 3통 요약'), findsOneWidget);
    expect(find.textContaining('이어서 지시하기'), findsOneWidget);
  });

  testWidgets('다른 대화가 진행 중이면 읽기 전용으로 열린다', (tester) async {
    final running = chat('진행 중인 작업', '')..lastResult = null;
    final old = chat('지난 작업', '지난 결과');
    history
      ..add(running)
      ..add(old);
    await agent.openSession(running.id);
    agent.onStatus(AgentStatus.running);
    await tester.pumpWidget(app());

    await tester.tap(find.text('지난 작업'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(agent.current?.id, running.id); // 진행 중인 대화는 그대로
    expect(find.text('지난 결과'), findsOneWidget);
    expect(find.textContaining('볼 수만 있어요'), findsOneWidget);
    expect(find.textContaining('이어서 지시하기'), findsNothing);
  });
}
