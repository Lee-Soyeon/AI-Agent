import 'dart:convert';

import 'package:ai_agent/github/github_store.dart';
import 'package:ai_agent/workfilter/github_upload_service.dart';
import 'package:ai_agent/workfilter/work_filter_models.dart';
import 'package:ai_agent/workfilter/work_filter_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

SharedItem _workItem(String id, DateTime at, String summary) {
  final item = SharedItem(id: id, receivedAt: at, rawText: '원문 $id');
  item.status = ShareItemStatus.done;
  item.classification = WorkClassification(isWork: true, contentType: '통화', summary: summary);
  item.uploadStatus = UploadStatus.pending;
  return item;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  test('하루치 업무 항목을 모아 브랜치·파일·PR 을 한 번에 만든다', () async {
    final day = DateTime(2026, 1, 2, 9, 30);
    final items = [
      _workItem('1', day, '김대리와 견적 논의'),
      _workItem('2', DateTime(2026, 1, 2, 14, 0), '박과장 미팅 일정 조율'),
      _workItem('3', DateTime(2026, 1, 1, 9, 0), '다른 날짜(전날) 항목 — 섞이면 안 됨'),
    ];
    final calls = <String>[];
    String? putBody;

    final client = MockClient((req) async {
      calls.add('${req.method} ${req.url.path}?${req.url.query}');
      if (req.method == 'GET' && req.url.path == '/repos/o/r') {
        return http.Response(jsonEncode({'default_branch': 'main'}), 200);
      }
      if (req.method == 'GET' && req.url.path.endsWith('/git/ref/heads/worklog/2026-01-02')) {
        return http.Response('not found', 404);
      }
      if (req.method == 'GET' && req.url.path.endsWith('/git/ref/heads/main')) {
        return http.Response(jsonEncode({'object': {'sha': 'base-sha'}}), 200);
      }
      if (req.method == 'POST' && req.url.path.endsWith('/git/refs')) {
        return http.Response(jsonEncode({'ref': 'refs/heads/worklog/2026-01-02'}), 201);
      }
      if (req.method == 'GET' && req.url.path.contains('/contents/worklog/2026-01-02.md')) {
        return http.Response('not found', 404);
      }
      if (req.method == 'PUT' && req.url.path.contains('/contents/worklog/2026-01-02.md')) {
        putBody = req.body;
        return http.Response(jsonEncode({'content': {'sha': 'newsha'}}), 200);
      }
      if (req.method == 'GET' && req.url.path.endsWith('/pulls')) {
        return http.Response(jsonEncode([]), 200);
      }
      if (req.method == 'POST' && req.url.path.endsWith('/pulls')) {
        return http.Response(
          jsonEncode({'number': 42, 'html_url': 'https://github.com/o/r/pull/42'}),
          201,
        );
      }
      return http.Response('unexpected ${req.method} ${req.url.path}', 500);
    });

    final github = GithubStore(client: client);
    github.token = 't';
    github.owner = 'o';
    github.repo = 'r';
    final store = WorkFilterStore();
    for (final i in items) {
      await store.upsert(i);
    }

    final url = await const GithubUploadService().uploadDay(
      dayKey: '2026-01-02',
      items: store.items,
      github: github,
      store: store,
    );

    expect(url, 'https://github.com/o/r/pull/42');
    final body = jsonDecode(putBody!) as Map;
    final content = utf8.decode(base64.decode(body['content'] as String));
    expect(content, contains('김대리와 견적 논의'));
    expect(content, contains('박과장 미팅 일정 조율'));
    expect(content, isNot(contains('다른 날짜(전날) 항목')));
    expect(body.containsKey('sha'), isFalse); // 새 파일이라 sha 없이 보내야 함

    final updated1 = store.items.firstWhere((i) => i.id == '1');
    final updated2 = store.items.firstWhere((i) => i.id == '2');
    final updated3 = store.items.firstWhere((i) => i.id == '3');
    expect(updated1.uploadStatus, UploadStatus.uploaded);
    expect(updated1.prUrl, 'https://github.com/o/r/pull/42');
    expect(updated2.uploadStatus, UploadStatus.uploaded);
    expect(updated3.uploadStatus, UploadStatus.pending); // 다른 날짜는 건드리지 않음
  });

  test('올릴 업무 항목이 없으면 null 을 돌려주고 네트워크를 타지 않는다', () async {
    var called = false;
    final client = MockClient((req) async {
      called = true;
      return http.Response('', 500);
    });
    final github = GithubStore(client: client);
    github.token = 't';
    github.owner = 'o';
    github.repo = 'r';
    final store = WorkFilterStore();
    final personal = SharedItem(id: '1', receivedAt: DateTime.now(), rawText: 'x');
    personal.classification = const WorkClassification(isWork: false, contentType: '문자', summary: 's');
    personal.uploadStatus = UploadStatus.skippedNotWork;
    await store.upsert(personal);

    final url = await const GithubUploadService().uploadDay(
      dayKey: '${DateTime.now().year}-01-01',
      items: store.items,
      github: github,
      store: store,
    );
    expect(url, isNull);
    expect(called, isFalse);
  });

  test('GitHub 이 연결 안 되어 있으면 예외를 던진다', () async {
    final github = GithubStore(client: MockClient((req) async => http.Response('', 500)));
    final store = WorkFilterStore();
    final item = _workItem('1', DateTime.now(), 's');
    await store.upsert(item);
    await expectLater(
      const GithubUploadService().uploadDay(
        dayKey: item.dayKey,
        items: store.items,
        github: github,
        store: store,
      ),
      throwsA(isA<GithubUploadException>()),
    );
  });
}
