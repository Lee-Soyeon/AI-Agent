import 'dart:io';

import 'package:ai_agent/agent/agent_models.dart';
import 'package:ai_agent/agent/agent_runner.dart';
import 'package:ai_agent/agent/prompts.dart';
import 'package:ai_agent/browser/agent_browser.dart';
import 'package:ai_agent/browser/sites.dart';
import 'package:ai_agent/llm/llm_types.dart';
import 'package:ai_agent/services/service_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

class _Llm implements LlmProvider {
  _Llm(this.turns);
  final List<LlmResponse> turns;
  final seen = <List<ChatMessage>>[];
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

class _Hooks implements AgentHooks {
  @override
  void onLog(AgentLogEntry entry) {}
  @override
  void onStatus(AgentStatus status) {}
  @override
  void onScreenshot(List<int> jpeg) {}
  @override
  Future<ApprovalDecision> requestApproval(ApprovalRequest request) async =>
      const ApprovalDecision(approved: false);
  @override
  Future<String> askUser(UserQuestion question) async => '';
  @override
  Future<String?> requestUserHelp(String reason, String? url) async => url;
}

void main() {
  final catalog = ServiceCatalog.fromJson(File(ServiceCatalog.assetPath).readAsStringSync());

  test('앱과 서버가 같은 카탈로그를 쓰고, 100개 이상이며 형식이 올바르다', () {
    expect(catalog.services.length, greaterThanOrEqualTo(100));
    expect(catalog.services.map((s) => s.id).toSet().length, catalog.services.length);
    for (final s in catalog.services) {
      if (s.supported) {
        expect(Uri.parse(s.home!).scheme, 'https', reason: s.id);
      } else {
        expect(s.note, isNotNull, reason: '${s.id}: 지원 안 하는 이유 필요');
      }
      if (s.search != null) expect(s.search, contains('{q}'), reason: s.id);
    }
    // 폰 모드의 전용 사이트 설정(쿠팡)도 카탈로그에 있어야 한다
    for (final site in allSites) {
      expect(catalog.find(site.id), isNotEmpty);
    }
  });

  test('검색·설명·프롬프트 목록', () {
    expect(catalog.find('네이버지도').single.id, 'naver_map');
    expect(
      catalog.find('쿠팡').first.searchUrl('제로 콜라'),
      'https://m.coupang.com/nm/search?q=%EC%A0%9C%EB%A1%9C%20%EC%BD%9C%EB%9D%BC',
    );
    expect(catalog.find('배달의민족').single.describe(), contains('지원하지 않음'));
    final prompt = buildSystemPrompt(loginState: const {}, serviceIndex: catalog.promptIndex());
    expect(prompt, contains('코레일'));
    expect(prompt, isNot(contains('browse.gmarket.co.kr'))); // 상세 URL 은 도구로만
  });

  test('폰 모드 에이전트의 service_info 도구', () async {
    final llm = _Llm([
      const LlmResponse(
        toolCalls: [
          ToolCall(id: 'a', name: 'service_info', arguments: {'service': 'G마켓', 'keyword': '생수'}),
        ],
      ),
      const LlmResponse(text: '끝'),
    ]);
    await AgentRunner(
      llm: llm,
      browser: _NoBrowser(),
      hooks: _Hooks(),
      systemPrompt: 's',
      catalog: catalog,
    ).run('x');
    final result = llm.seen[1].lastWhere((m) => m.role == ChatRole.tool).text!;
    expect(result, contains('https://browse.gmarket.co.kr/search?keyword=%EC%83%9D%EC%88%98'));
  });
}

/// service_info 는 브라우저를 쓰지 않으므로, 호출되면 실패하는 가짜.
class _NoBrowser implements BrowserDriver {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('브라우저를 쓰면 안 됨');
}
