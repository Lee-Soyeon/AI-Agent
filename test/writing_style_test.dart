import 'dart:convert';

import 'package:ai_agent/google/gmail_api.dart';
import 'package:ai_agent/google/writing_style.dart';
import 'package:ai_agent/llm/llm_types.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _EchoLlm implements LlmProvider {
  String? system;
  String? prompt;
  List<ToolSpec>? tools;

  @override
  String get displayName => 'fake';

  @override
  Future<LlmResponse> complete({
    required String system,
    required List<ChatMessage> messages,
    required List<ToolSpec> tools,
  }) async {
    this.system = system;
    prompt = messages.single.text;
    this.tools = tools;
    return const LlmResponse(text: '## 인사말\n"OO님 안녕하세요," 로 시작\n## 서명\n이소연 드림');
  }
}

String b64(String s) => base64Url.encode(utf8.encode(s)).replaceAll('=', '');

void main() {
  group('cleanSentBody: 인용된 이전 메일 제거', () {
    test('Gmail 한국어 답장 인용', () {
      expect(
        cleanSentBody('네 확인했습니다.\n\n이소연 드림\n\n2026년 9월 1일 (월) 오전 9:00, 김과장 <k@a.com>님이 작성:\n> 원문'),
        '네 확인했습니다.\n\n이소연 드림',
      );
    });

    test('영문 답장 / Outlook 원본 메시지 / 전달', () {
      expect(
        cleanSentBody(
          'Thanks!\nSoyeon\n\nOn Mon, Sep 1, 2026 at 9:00 AM Kim <k@a.com> wrote:\n> hi',
        ),
        'Thanks!\nSoyeon',
      );
      expect(cleanSentBody('검토 부탁드립니다.\n-----Original Message-----\nFrom: x'), '검토 부탁드립니다.');
      expect(cleanSentBody('참고하세요.\n---------- Forwarded message ---------\n보낸사람: x'), '참고하세요.');
    });

    test('> 인용 줄은 빼고 본문 중간 내용은 유지, 길이 제한', () {
      expect(cleanSentBody('> 질문\n답변입니다.'), '답변입니다.');
      expect(cleanSentBody('가' * 50, maxChars: 10), '${'가' * 10}…');
    });
  });

  test('learn: 보낸 메일을 여러 페이지에서 모아 분석하고 결과를 저장한다', () async {
    final queries = <String>[];
    var reads = 0;
    final client = MockClient((req) async {
      if (req.url.path.endsWith('/messages')) {
        queries.add(req.url.queryParameters['q']!);
        final page = req.url.queryParameters['pageToken'];
        return http.Response(
          jsonEncode({
            'messages': [
              for (var i = 0; i < 3; i++) {'id': '${page ?? 'p1'}-$i'},
            ],
            if (page == null) 'nextPageToken': 'p2',
          }),
          200,
        );
      }
      reads++;
      final id = req.url.pathSegments.last;
      return http.Response.bytes(
        utf8.encode(
          jsonEncode({
            'id': id,
            'threadId': 't',
            'payload': {
              'mimeType': 'text/plain',
              'headers': [
                {'name': 'To', 'value': 'client$id@example.com'},
                {'name': 'Subject', 'value': '제목 $id'},
              ],
              'body': {
                'data': b64('고객님 안녕하세요,\n본문 $id 입니다.\n\n이소연 드림\n\nOn Mon wrote:\n> 상대 원문 $id'),
              },
            },
          }),
        ),
        200,
      );
    });
    final gmail = GmailApi(
      authHeaders: ({refresh = false, staleToken}) async => {'Authorization': 'Bearer t'},
      client: client,
    );
    final llm = _EchoLlm();
    final storage = MemoryStyleProfileStore();
    final store = WritingStyleStore(store: storage);

    await store.learn(llm: llm, gmail: gmail, sampleSize: 5);

    expect(store.error, isNull);
    expect(queries, ['in:sent', 'in:sent']); // 두 페이지
    expect(reads, 5);
    expect(llm.tools, isEmpty);
    expect(llm.prompt, contains('사용자가 직접 보낸 이메일 5통'));
    expect(llm.prompt, contains('본문 p1-0 입니다.'));
    expect(llm.prompt, isNot(contains('상대 원문'))); // 인용문은 LLM 에 보내지 않음
    expect(store.profile!.analyzedCount, 5);
    expect(store.profile!.guide, contains('이소연 드림'));

    // 앱 재시작 후 복원, 사용자가 직접 수정
    final restored = WritingStyleStore(store: storage);
    await restored.load();
    await restored.updateGuide('서명: 이소연 올림');
    expect(restored.profile!.guide, '서명: 이소연 올림');
    expect(restored.profile!.analyzedCount, 5);
  });

  test('learn: 보낸 메일이 너무 적으면 LLM 을 부르지 않고 오류', () async {
    final gmail = GmailApi(
      authHeaders: ({refresh = false, staleToken}) async => {'Authorization': 'Bearer t'},
      client: MockClient((req) async => http.Response(jsonEncode({'messages': []}), 200)),
    );
    final llm = _EchoLlm();
    final store = WritingStyleStore(store: MemoryStyleProfileStore());
    await store.learn(llm: llm, gmail: gmail);
    expect(llm.prompt, isNull);
    expect(store.error, contains('부족'));
    expect(store.profile, isNull);
  });
}
