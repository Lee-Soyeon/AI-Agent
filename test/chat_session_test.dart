import 'dart:io';
import 'dart:typed_data';

import 'package:ai_agent/agent/agent_models.dart';
import 'package:ai_agent/agent/agent_runner.dart';
import 'package:ai_agent/agent/chat_session.dart';
import 'package:ai_agent/llm/llm_types.dart';
import 'package:ai_agent/ui/history_screen.dart' show formatWhen;
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;

  setUp(() async => dir = await Directory.systemTemp.createTemp('chat_sessions_test'));
  tearDown(() async => dir.delete(recursive: true));

  ChatSession sample() {
    final s = ChatSession.create('쿠팡에서 삼다수 담아줘\n두 번째 줄', vendor: 'anthropic');
    s.status = AgentStatus.finished;
    s.lastResult = '장바구니에 담았습니다';
    s.logs.addAll([
      AgentLogEntry(LogKind.user, '쿠팡에서 삼다수 담아줘'),
      AgentLogEntry(LogKind.observation, '쿠팡', detail: 'x' * 30000),
      AgentLogEntry(LogKind.result, '장바구니에 담았습니다'),
    ]);
    s.messages.addAll([
      ChatMessage.user('쿠팡에서 삼다수 담아줘'),
      ChatMessage.assistant(
        text: '열어볼게요',
        toolCalls: const [
          ToolCall(id: 't1', name: 'open_url', arguments: {'url': 'https://m.coupang.com'}),
        ],
        providerRaw: [
          {'type': 'text', 'text': '열어볼게요'},
        ],
      ),
      ChatMessage.toolResult(toolCallId: 't1', toolName: 'open_url', content: '열었습니다'),
    ]);
    return s;
  }

  test('대화는 파일로 저장되고 다시 불러와진다 (LLM 대화·마지막 화면 포함)', () async {
    final store = ChatSessionStore(directory: dir);
    final s = sample()
      ..screenshot = Uint8List.fromList([0xff, 0xd8, 1, 2])
      ..screenshotDirty = true;
    store.add(s);
    expect(s.title, '쿠팡에서 삼다수 담아줘');
    await store.flush();

    final reloaded = ChatSessionStore(directory: dir);
    await reloaded.load();
    final r = reloaded.byId(s.id)!;
    expect(r.title, s.title);
    expect(r.status, AgentStatus.finished);
    expect(r.lastResult, '장바구니에 담았습니다');
    expect(r.vendor, 'anthropic');
    expect(r.logs.map((l) => l.kind), [LogKind.user, LogKind.observation, LogKind.result]);
    expect(r.logs[1].detail!.length, lessThan(21000)); // 긴 스냅샷은 잘라서 저장
    expect(r.messages.map((m) => m.role), [ChatRole.user, ChatRole.assistant, ChatRole.tool]);
    expect(r.messages[1].toolCalls.single.arguments['url'], 'https://m.coupang.com');
    expect(r.messages[1].providerRaw, isA<List>());
    expect(r.messages[2].toolCallId, 't1');
    expect(r.screenshot, isNull); // 화면은 열 때 읽는다
    expect(await reloaded.loadScreenshot(r), [0xff, 0xd8, 1, 2]);
  });

  test('기기에서 진행 중이던 대화는 앱을 다시 켜면 중단됨으로 표시된다', () async {
    final store = ChatSessionStore(directory: dir);
    final local = sample()..status = AgentStatus.running;
    final remote = ChatSession.create('서버 작업', remoteTaskId: 'abc')
      ..status = AgentStatus.waitingApproval;
    store
      ..add(local)
      ..add(remote);
    await store.flush();

    final reloaded = ChatSessionStore(directory: dir);
    await reloaded.load();
    expect(reloaded.byId(local.id)!.status, AgentStatus.cancelled);
    expect(reloaded.byId(local.id)!.logs.last.text, contains('중단'));
    // 서버 작업은 서버에서 계속되므로 그대로 둔다
    expect(reloaded.byRemoteTaskId('abc')!.status, AgentStatus.waitingApproval);
  });

  test('목록은 최근에 바뀐 순이고, 삭제하면 파일도 지워진다', () async {
    final store = ChatSessionStore(directory: dir);
    final a = ChatSession.create('a', vendor: 'openai');
    final b = ChatSession.create('b', vendor: 'openai');
    store
      ..add(a)
      ..add(b);
    a.updatedAt = DateTime(2020);
    b.updatedAt = DateTime(2021);
    expect(store.sessions.map((s) => s.title), ['b', 'a']);
    store.save(a); // 바뀌면 맨 위로
    expect(store.sessions.first.title, 'a');
    await store.flush();

    await store.delete(a.id);
    expect(store.byId(a.id), isNull);
    expect(dir.listSync().map((f) => f.uri.pathSegments.last), ['${b.id}.json']);
  });

  test('도중에 끊긴 tool call 은 결과를 채워 이어서 보낼 수 있게 한다', () {
    final messages = [
      ChatMessage.user('결제해줘'),
      ChatMessage.assistant(
        toolCalls: const [
          ToolCall(id: 'a', name: 'read_page', arguments: {}),
          ToolCall(id: 'b', name: 'request_approval', arguments: {}),
        ],
      ),
      ChatMessage.toolResult(toolCallId: 'a', toolName: 'read_page', content: '페이지'),
    ];
    AgentRunner.repairHistory(messages);
    expect(messages.map((m) => m.toolCallId), [null, null, 'a', 'b']);
    expect(messages.last.text, contains('중단'));

    AgentRunner.repairHistory(messages); // 이미 온전하면 그대로
    expect(messages.length, 4);
  });

  test('다른 공급자로 이어갈 때 원본 응답을 버린다', () {
    final m = ChatMessage.assistant(text: 'hi', providerRaw: const ['raw']);
    final stripped = m.withoutProviderRaw();
    expect(stripped.providerRaw, isNull);
    expect(stripped.text, 'hi');
  });

  test('시간 표시', () {
    final now = DateTime(2026, 9, 24, 15);
    expect(formatWhen(now.subtract(const Duration(seconds: 10)), now: now), '방금');
    expect(formatWhen(now.subtract(const Duration(minutes: 5)), now: now), '5분 전');
    expect(formatWhen(DateTime(2026, 9, 24, 9), now: now), '6시간 전');
    expect(formatWhen(DateTime(2026, 9, 23, 22), now: now), '어제');
    expect(formatWhen(DateTime(2026, 3, 1), now: now), '3월 1일');
    expect(formatWhen(DateTime(2025, 3, 1), now: now), '2025.3.1');
  });
}
