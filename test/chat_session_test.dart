import 'dart:async';
import 'dart:io';

import 'package:ai_agent/agent/agent_controller.dart';
import 'package:ai_agent/agent/agent_models.dart';
import 'package:ai_agent/agent/agent_runner.dart';
import 'package:ai_agent/agent/chat_session.dart';
import 'package:ai_agent/browser/session_store.dart';
import 'package:ai_agent/core/settings_store.dart';
import 'package:ai_agent/google/google_auth.dart';
import 'package:ai_agent/google/writing_style.dart';
import 'package:ai_agent/llm/llm_types.dart';
import 'package:ai_agent/openai/chatgpt_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ScriptedLlm implements LlmProvider {
  _ScriptedLlm(this.turns);
  final List<LlmResponse> turns;
  final List<List<ChatMessage>> seen = [];

  @override
  String get displayName => 'fake';

  @override
  Future<LlmResponse> complete({
    required String system,
    required List<ChatMessage> messages,
    required List<ToolSpec> tools,
  }) async {
    seen.add(List.of(messages));
    return turns.removeAt(0);
  }
}

/// LLM 을 가짜로 바꾼 설정.
class _FakeSettings extends SettingsStore {
  _FakeSettings(this.llm) : super(chatgpt: ChatGptAuth(store: MemoryChatGptTokenStore()));
  final LlmProvider llm;

  @override
  bool get isLocalLlmConfigured => true;

  @override
  LlmProvider createProvider() => llm;
}

Future<void> until(bool Function() cond) async {
  final end = DateTime.now().add(const Duration(seconds: 5));
  while (!cond()) {
    if (DateTime.now().isAfter(end)) throw TimeoutException('조건을 기다리다 시간 초과');
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('chat_history_test');
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() async => dir.delete(recursive: true));

  AgentController controller(SettingsStore settings) => AgentController(
    settings: settings,
    sessions: SiteSessionStore(),
    google: GoogleAuthService(),
    writingStyle: WritingStyleStore(store: MemoryStyleProfileStore()),
    navigatorKey: GlobalKey<NavigatorState>(),
    historyFiles: ChatHistoryFiles(directory: dir),
  );

  test('이 폰에서 실행한 대화는 앱을 다시 켜도 LLM 대화를 되살려 이어서 지시할 수 있다', () async {
    final llm1 = _ScriptedLlm([
      LlmResponse(
        toolCalls: const [
          ToolCall(id: 'a', name: 'finish', arguments: {'summary': '메일 3통 요약'}),
        ],
      ),
    ]);
    final first = controller(_FakeSettings(llm1));
    await first.init();
    await first.startTask('메일 요약해줘');
    expect(first.lastResult, '메일 3통 요약');
    await until(() => first.chats.single.hasSavedHistory); // 잠깐 모았다가 저장된다
    first.dispose();

    // 앱을 다시 켠 것처럼 새 컨트롤러가 저장본을 불러온다
    final llm2 = _ScriptedLlm([const LlmResponse(text: '두 번째 메일에 답장했어요')]);
    final second = controller(_FakeSettings(llm2));
    await second.init();
    final s = second.chats.single;
    expect(s.title, '메일 요약해줘');
    expect(s.runner, isNull);
    expect(s.canContinue, isTrue);

    second.openSession(s.id);
    expect(second.hasConversation, isTrue);
    await second.followUp('두 번째 메일에 답장 써줘');

    expect(second.lastResult, '두 번째 메일에 답장했어요');
    expect(llm2.seen.single.map((m) => m.role), [
      ChatRole.user,
      ChatRole.assistant,
      ChatRole.tool,
      ChatRole.user,
    ]);
    expect(llm2.seen.single.first.text, '메일 요약해줘');

    // 삭제하면 LLM 대화 파일도 지운다
    second.deleteSession(s.id);
    await until(() => dir.listSync().isEmpty);
    second.dispose();
  });

  test('LLM 대화 파일이 없으면 이어서 지시하지 않고 안내한다', () async {
    SharedPreferences.setMockInitialValues({
      'chat_sessions':
          '[{"id":"x","title":"쿠팡","status":"finished","hasSavedHistory":true,"logs":[]}]',
    });
    final llm = _ScriptedLlm([]);
    final agent = controller(_FakeSettings(llm));
    await agent.init();
    agent.openSession('x');
    await agent.followUp('계속');
    expect(llm.seen, isEmpty);
    expect(agent.logs.last.text, contains('저장된 대화를 읽지 못해'));
    expect(agent.current.canContinue, isFalse);
    agent.dispose();
  });

  test('ChatSession 은 공급자와 LLM 대화 저장 여부를 기억한다', () {
    final s = ChatSession(id: 'a', title: 't', vendor: 'anthropic', hasSavedHistory: true)
      ..status = AgentStatus.running;
    final r = ChatSession.fromJson(s.toJson());
    expect(r.vendor, 'anthropic');
    expect(r.hasSavedHistory, isTrue);
    expect(r.status, AgentStatus.cancelled); // 앱이 꺼지며 멈춘 작업
    expect(r.canContinue, isTrue);
  });

  test('LLM 대화 파일 저장/불러오기 (도구 호출·공급자 원본 포함)', () async {
    final files = ChatHistoryFiles(directory: dir);
    expect(await files.load('none'), isNull);
    expect(
      await files.save('a', [
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
      ]),
      isTrue,
    );
    final m = (await files.load('a'))!;
    expect(m.map((e) => e.role), [ChatRole.user, ChatRole.assistant, ChatRole.tool]);
    expect(m[1].toolCalls.single.arguments['url'], 'https://m.coupang.com');
    expect(m[1].providerRaw, isA<List>());
    expect(m[1].withoutProviderRaw().providerRaw, isNull);
    expect(m[2].toolCallId, 't1');
    await files.delete('a');
    expect(await files.load('a'), isNull);
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
}
