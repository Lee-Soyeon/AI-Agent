// 실제 Python 서버(server/)와 앱 컨트롤러가 주고받는 계약을 검증한다.
// AGENT_SERVER_PYTHON=<server 의존성이 설치된 python> 이 있을 때만 실행된다.
import 'dart:async';
import 'dart:io';

import 'package:ai_agent/agent/agent_controller.dart';
import 'package:ai_agent/agent/agent_models.dart';
import 'package:ai_agent/browser/session_store.dart';
import 'package:ai_agent/core/settings_store.dart';
import 'package:ai_agent/google/google_auth.dart';
import 'package:ai_agent/google/writing_style.dart';
import 'package:ai_agent/openai/chatgpt_auth.dart';
import 'package:ai_agent/remote/agent_server_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> until(bool Function() cond, {Duration timeout = const Duration(seconds: 15)}) async {
  final end = DateTime.now().add(timeout);
  while (!cond()) {
    if (DateTime.now().isAfter(end)) throw TimeoutException('조건을 기다리다 시간 초과');
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

void main() {
  final python = Platform.environment['AGENT_SERVER_PYTHON'];
  final skip = python == null ? 'AGENT_SERVER_PYTHON 이 없어 건너뜀' : null;
  late Process server;
  late String baseUrl;

  setUpAll(() async {
    if (python == null) return;
    TestWidgetsFlutterBinding.ensureInitialized();
    HttpOverrides.global = null; // 테스트 바인딩이 막아 둔 실제 HTTP 를 허용
    final socket = await ServerSocket.bind('127.0.0.1', 0);
    final port = socket.port;
    await socket.close();
    server = await Process.start(python, [
      '-m',
      'tests.e2e_server',
      '$port',
    ], workingDirectory: 'server');
    server.stderr.transform(const SystemEncoding().decoder).listen(stderr.write);
    baseUrl = 'http://127.0.0.1:$port';
    final client = HttpClient();
    for (var i = 0; i < 100; i++) {
      try {
        final req = await client.getUrl(Uri.parse('$baseUrl/health'));
        if ((await req.close()).statusCode == 200) break;
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  });

  tearDownAll(() {
    if (python != null) server.kill();
  });

  test('잘못된 토큰은 거부', () async {
    final c = AgentServerClient(baseUrl: baseUrl, token: 'wrong');
    await expectLater(c.ping(), throwsA(isA<AgentServerException>()));
    expect(
      AgentServerClient(baseUrl: '$baseUrl/', token: 't').liveUri.toString(),
      '${baseUrl.replaceFirst('http', 'ws')}/live?token=t',
    );
  }, skip: skip);

  test('서버 모드: 작업 → 승인 → 질문 → 완료 → 후속 지시', () async {
    final settings = SettingsStore(chatgpt: ChatGptAuth(store: MemoryChatGptTokenStore()))
      ..runOnServer = true
      ..serverUrl = baseUrl
      ..serverToken = 'e2e-token';
    await settings.serverClient!.ping();
    final agent = AgentController(
      settings: settings,
      sessions: SiteSessionStore(),
      google: GoogleAuthService(),
      writingStyle: WritingStyleStore(store: MemoryStyleProfileStore()),
      navigatorKey: GlobalKey<NavigatorState>(),
    );

    await agent.startTask('생수 주문해줘');
    await until(() => agent.pendingApproval != null);
    expect(agent.status, AgentStatus.waitingApproval);
    expect(agent.pendingApproval!.kind, ApprovalKind.purchase);
    expect(agent.pendingApproval!.summary, contains('9,900원'));
    expect(agent.lastScreenshot, isNotNull);

    agent.resolveApproval(true);
    await until(() => agent.pendingQuestion != null);
    expect(agent.pendingQuestion!.choices, ['예', '아니오']);

    agent.answerQuestion('아니오');
    await until(() => agent.status == AgentStatus.finished);
    expect(agent.lastResult, '주문 완료');
    final texts = agent.logs.map((l) => l.text).join('\n');
    expect(texts, contains('생수 주문해줘'));
    expect(texts, contains('사용자가 승인했습니다'));
    expect(texts, contains('승인된 동작 실행'));
    expect(agent.logs.where((l) => l.kind == LogKind.user).map((l) => l.text), contains('아니오'));
    expect(agent.hasConversation, isTrue);

    await agent.followUp('고마워');
    await until(() => agent.status == AgentStatus.finished && agent.lastResult == '후속 답변');

    // 대화는 목록에 남고, 새 채팅을 열었다가 다시 열면 로그가 그대로 보인다
    final session = agent.chats.single;
    expect(session.remoteTaskId, isNotNull);
    expect(session.title, '생수 주문해줘');
    expect(session.status, AgentStatus.finished);
    final logCount = agent.logs.length;
    agent.newSession();
    expect(agent.logs, isEmpty);
    agent.openSession(session.id);
    expect(agent.logs.length, logCount);
    expect(agent.lastResult, '후속 답변');
    expect(agent.hasConversation, isTrue);
    expect((await settings.serverClient!.listTasks()).single.id, session.remoteTaskId);

    // 앱을 새로 켠 것처럼 새 컨트롤러가 서버의 현재 작업에 다시 붙는다
    final reopened = AgentController(
      settings: settings,
      sessions: SiteSessionStore(),
      google: GoogleAuthService(),
      writingStyle: WritingStyleStore(store: MemoryStyleProfileStore()),
      navigatorKey: GlobalKey<NavigatorState>(),
    );
    await reopened.attachToServer();
    await until(() => reopened.lastResult == '후속 답변');
    expect(reopened.logs.length, agent.logs.length);
    expect(reopened.chats.single.remoteTaskId, session.remoteTaskId);
    expect(reopened.chats.single.title, '생수 주문해줘');

    // 대화를 지우면 서버 기록도 지운다
    agent.deleteSession(session.id);
    expect(agent.chats, isEmpty);
    final client = settings.serverClient!;
    for (var i = 0; i < 50 && (await client.listTasks()).isNotEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(await client.listTasks(), isEmpty);
    agent.dispose();
    reopened.dispose();
  }, skip: skip);
}
