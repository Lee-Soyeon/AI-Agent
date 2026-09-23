import 'dart:convert';
import 'dart:typed_data';

import 'package:ai_agent/agent/agent_models.dart';
import 'package:ai_agent/agent/agent_runner.dart';
import 'package:ai_agent/agent/safety.dart';
import 'package:ai_agent/browser/agent_browser.dart';
import 'package:ai_agent/google/gmail_api.dart';
import 'package:ai_agent/llm/llm_types.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

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

class _FakeBrowser implements BrowserDriver {
  final labels = {1: '장바구니 담기', 2: '결제하기', 3: '비밀번호'};
  final clicked = <int>[];

  @override
  Future<void> navigate(String url) async {}
  @override
  Future<String?> currentUrl() async => 'https://m.coupang.com/';
  @override
  Future<PageSnapshot> snapshot() async => PageSnapshot({
    'url': 'https://m.coupang.com/',
    'title': '쿠팡',
    'text': '본문',
    'elements': [
      for (final e in labels.entries) {'id': e.key, 'tag': 'button', 'label': e.value},
    ],
  });
  @override
  Future<Map<String, dynamic>> describe(int id) async => {
    'ok': labels.containsKey(id),
    'label': labels[id],
    'type': id == 3 ? 'password' : '',
  };
  @override
  Future<Map<String, dynamic>> click(int id) async {
    clicked.add(id);
    return {'ok': true};
  }

  @override
  Future<Map<String, dynamic>> typeText(int id, String text, {bool submit = false}) async => {
    'ok': true,
  };
  @override
  Future<Map<String, dynamic>> scroll(String direction) async => {'ok': true};
  @override
  Future<void> goBack() async {}
  @override
  Future<Uint8List?> screenshot() async => null;
}

class _Hooks implements AgentHooks {
  _Hooks({this.approve = true});
  final bool approve;
  final logs = <AgentLogEntry>[];
  int approvals = 0;
  ApprovalRequest? lastApproval;

  @override
  void onLog(AgentLogEntry entry) => logs.add(entry);
  @override
  void onStatus(AgentStatus status) {}
  @override
  void onScreenshot(List<int> jpeg) {}
  @override
  Future<ApprovalDecision> requestApproval(ApprovalRequest request) async {
    approvals++;
    lastApproval = request;
    return ApprovalDecision(approved: approve, feedback: approve ? null : '다른 상품으로');
  }

  @override
  Future<String> askUser(UserQuestion question) async => '네';
  @override
  Future<String?> requestUserHelp(String reason, String? url) async => url;
}

LlmResponse _call(String name, Map<String, dynamic> args, [String id = 'x']) => LlmResponse(
  toolCalls: [ToolCall(id: id, name: name, arguments: args)],
);

String _lastToolResult(List<ChatMessage> msgs) =>
    msgs.lastWhere((m) => m.role == ChatRole.tool).text!;

void main() {
  test('safety pattern: 결제/전송만 민감, 장바구니/구매하기는 아님', () {
    final p = SafetyPolicy();
    expect(p.isSensitive('결제하기'), isTrue);
    expect(p.isSensitive('32,900원 결제하기'), isTrue);
    expect(p.isSensitive('보내기'), isTrue);
    expect(p.isSensitive('Send'), isTrue);
    expect(p.isSensitive('장바구니 담기'), isFalse);
    expect(p.isSensitive('구매하기'), isFalse);
    expect(p.isSensitive('보낸편지함'), isFalse);
    expect(p.isSensitive('Sent'), isFalse);
  });

  test('승인 없이 결제 버튼 클릭은 차단되고, 승인 후 1회만 허용된다', () async {
    final llm = _ScriptedLlm([
      _call('click', {'element_id': 1}, 'a'),
      _call('click', {'element_id': 2}, 'b'), // 승인 전 → 차단
      _call('request_approval', {
        'kind': 'purchase',
        'title': '결제',
        'summary': '생수 1개 9,900원',
      }, 'c'),
      _call('click', {'element_id': 2}, 'd'), // 승인 후 → 허용
      _call('click', {'element_id': 2}, 'e'), // 승인 소진 → 차단
      _call('finish', {'summary': '완료'}, 'f'),
    ]);
    final browser = _FakeBrowser();
    final hooks = _Hooks();
    final runner = AgentRunner(llm: llm, browser: browser, hooks: hooks, systemPrompt: 's');

    final result = await runner.run('생수 사줘');

    expect(result, '완료');
    expect(browser.clicked, [1, 2]);
    expect(hooks.approvals, 1);
    expect(_lastToolResult(llm.seen[2]), contains('차단됨'));
    expect(_lastToolResult(llm.seen[5]), contains('차단됨'));
  });

  test('거절하면 피드백이 LLM 에게 전달되고 버튼은 눌리지 않는다', () async {
    final llm = _ScriptedLlm([
      _call('request_approval', {'kind': 'purchase', 'title': '결제', 'summary': '...'}, 'a'),
      _call('click', {'element_id': 2}, 'b'),
      const LlmResponse(text: '취소했습니다.'),
    ]);
    final browser = _FakeBrowser();
    final runner = AgentRunner(
      llm: llm,
      browser: browser,
      hooks: _Hooks(approve: false),
      systemPrompt: 's',
    );

    expect(await runner.run('사줘'), '취소했습니다.');
    expect(browser.clicked, isEmpty);
    expect(_lastToolResult(llm.seen[1]), contains('다른 상품으로'));
  });

  test('비밀번호 입력창에는 입력하지 않는다', () async {
    final llm = _ScriptedLlm([
      _call('type_text', {'element_id': 3, 'text': 'hunter2'}),
      const LlmResponse(text: '끝'),
    ]);
    final runner = AgentRunner(
      llm: llm,
      browser: _FakeBrowser(),
      hooks: _Hooks(),
      systemPrompt: 's',
    );
    await runner.run('로그인해');
    expect(_lastToolResult(llm.seen[1]), contains('비밀번호'));
  });

  test('오래된 페이지 스냅샷은 요약된다', () {
    final msgs = <ChatMessage>[
      for (var i = 0; i < 4; i++)
        ChatMessage.toolResult(
          toolCallId: '$i',
          toolName: 'read_page',
          content: '결과\n\n${AgentRunner.snapshotHeader}\nURL: https://a/$i\n긴 본문',
        ),
    ];
    AgentRunner.compactHistory(msgs);
    expect(msgs[0].text, contains('생략됨 — https://a/0'));
    expect(msgs[1].text, contains('생략됨'));
    expect(msgs[2].text, contains('긴 본문'));
    expect(msgs[3].text, contains('긴 본문'));
  });

  group('gmail_send', () {
    late List<Map<String, dynamic>> posts;
    late GmailApi api;

    setUp(() {
      posts = [];
      api = GmailApi(
        authHeaders: ({refresh = false, staleToken}) async => {'Authorization': 'Bearer t'},
        client: MockClient((req) async {
          posts.add(jsonDecode(req.body) as Map<String, dynamic>);
          return http.Response(jsonEncode({'id': 'sent-1'}), 200);
        }),
      );
    });

    LlmResponse send() => _call('gmail_send', {
      'to': ['kim@example.com'],
      'subject': '회의 일정',
      'body': '내일 3시에 뵙겠습니다.',
    });

    test('승인하면 승인 카드에 보인 내용 그대로 한 번만 보낸다', () async {
      final llm = _ScriptedLlm([send(), const LlmResponse(text: '보냈습니다')]);
      final hooks = _Hooks();
      final runner = AgentRunner(
        llm: llm,
        browser: _FakeBrowser(),
        hooks: hooks,
        systemPrompt: 's',
        gmail: api,
        gmailAddress: 'me@gmail.com',
      );
      await runner.run('김 과장에게 메일 보내줘');

      expect(hooks.approvals, 1);
      expect(hooks.lastApproval!.kind, ApprovalKind.sendEmail);
      expect(hooks.lastApproval!.summary, contains('kim@example.com'));
      expect(hooks.lastApproval!.details, '내일 3시에 뵙겠습니다.');
      expect(posts, hasLength(1));
      final mime = GmailApi.decodeBase64Url(posts.single['raw'] as String);
      expect(mime, contains('To: kim@example.com'));
      expect(_lastToolResult(llm.seen[1]), contains('전송 완료'));
    });

    test('거절하면 보내지 않고 의견을 돌려준다', () async {
      final llm = _ScriptedLlm([send(), const LlmResponse(text: '안 보냄')]);
      final runner = AgentRunner(
        llm: llm,
        browser: _FakeBrowser(),
        hooks: _Hooks(approve: false),
        systemPrompt: 's',
        gmail: api,
      );
      await runner.run('메일 보내줘');
      expect(posts, isEmpty);
      expect(_lastToolResult(llm.seen[1]), contains('다른 상품으로'));
    });

    test('잘못된 주소나 Gmail 미연결이면 승인 요청 없이 오류', () async {
      final llm = _ScriptedLlm([
        _call('gmail_send', {
          'to': ['not-an-email'],
          'subject': 's',
          'body': 'b',
        }),
        const LlmResponse(text: '끝'),
      ]);
      final hooks = _Hooks();
      await AgentRunner(
        llm: llm,
        browser: _FakeBrowser(),
        hooks: hooks,
        systemPrompt: 's',
        gmail: api,
      ).run('보내');
      expect(hooks.approvals, 0);
      expect(_lastToolResult(llm.seen[1]), contains('올바르지 않은 이메일'));

      final llm2 = _ScriptedLlm([send(), const LlmResponse(text: '끝')]);
      await AgentRunner(
        llm: llm2,
        browser: _FakeBrowser(),
        hooks: _Hooks(),
        systemPrompt: 's',
      ).run('보내');
      expect(_lastToolResult(llm2.seen[1]), contains('연결되어 있지 않습니다'));
    });
  });
}
