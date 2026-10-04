import 'package:ai_agent/llm/llm_types.dart';
import 'package:ai_agent/workfilter/work_filter_models.dart';
import 'package:ai_agent/workfilter/work_filter_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _ScriptedLlm implements LlmProvider {
  _ScriptedLlm(this.text);
  final String text;
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
    return LlmResponse(text: text);
  }
}

SharedItem _fakeItem() {
  final item = SharedItem(id: '1', receivedAt: DateTime.now(), rawText: '원문 내용입니다');
  item.classification = const WorkClassification(isWork: true, contentType: '통화', summary: '요약 테스트');
  return item;
}

void main() {
  final service = WorkFilterService();

  test('정상 형식 응답을 분류·요약으로 해석한다', () async {
    final llm = _ScriptedLlm('분류: 업무\n종류: 통화\n요약: 김대리가 내일 미팅 시간을 물어봄');
    final result = await service.classify('내일 3시에 미팅 가능하신가요?', llm);
    expect(result.isWork, isTrue);
    expect(result.contentType, '통화');
    expect(result.summary, '김대리가 내일 미팅 시간을 물어봄');
    expect(llm.seen.single.single.text, '내일 3시에 미팅 가능하신가요?');
  });

  test('개인 내용은 isWork=false 로 해석한다', () async {
    final llm = _ScriptedLlm('분류: 개인\n종류: 문자\n요약: 저녁 약속 잡는 중');
    final result = await service.classify('오늘 저녁에 뭐해?', llm);
    expect(result.isWork, isFalse);
  });

  test('형식이 완전히 깨지면 예외를 던진다', () async {
    final llm = _ScriptedLlm('');
    expect(() => service.classify('텍스트', llm), throwsA(isA<WorkFilterException>()));
  });

  test('Slack 메시지 본문에 요약과 원문 인용이 들어간다', () {
    final msg = service.buildSlackMessage(_fakeItem());
    expect(msg, contains('업무'));
    expect(msg, contains('통화'));
    expect(msg, contains('요약 테스트'));
    expect(msg, contains('> '));
  });
}
