import 'dart:convert';

import 'package:ai_agent/github/github_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('defaultBranch', () async {
    final client = MockClient((req) async {
      expect(req.url.path, '/repos/o/r');
      return http.Response(jsonEncode({'default_branch': 'main'}), 200);
    });
    final api = GithubApi(token: 't', owner: 'o', repo: 'r', client: client);
    expect(await api.defaultBranch(), 'main');
  });

  test('ensureBranch: 이미 있으면 새로 안 만든다', () async {
    var createCalled = false;
    final client = MockClient((req) async {
      if (req.url.path.endsWith('/git/ref/heads/worklog/2026-01-01')) {
        return http.Response(jsonEncode({'object': {'sha': 'abc'}}), 200);
      }
      createCalled = true;
      return http.Response('', 500);
    });
    final api = GithubApi(token: 't', owner: 'o', repo: 'r', client: client);
    final created = await api.ensureBranch('worklog/2026-01-01', fromBranch: 'main');
    expect(created, isFalse);
    expect(createCalled, isFalse);
  });

  test('ensureBranch: 없으면 기준 브랜치에서 새로 만든다', () async {
    final calls = <String>[];
    final client = MockClient((req) async {
      calls.add('${req.method} ${req.url.path}');
      if (req.url.path.endsWith('/git/ref/heads/worklog/2026-01-01')) {
        return http.Response('not found', 404);
      }
      if (req.url.path.endsWith('/git/ref/heads/main')) {
        return http.Response(jsonEncode({'object': {'sha': 'base-sha'}}), 200);
      }
      if (req.url.path.endsWith('/git/refs')) {
        final body = jsonDecode(req.body) as Map;
        expect(body['ref'], 'refs/heads/worklog/2026-01-01');
        expect(body['sha'], 'base-sha');
        return http.Response(jsonEncode({'ref': body['ref']}), 201);
      }
      return http.Response('unexpected', 500);
    });
    final api = GithubApi(token: 't', owner: 'o', repo: 'r', client: client);
    final created = await api.ensureBranch('worklog/2026-01-01', fromBranch: 'main');
    expect(created, isTrue);
    expect(calls, contains('POST /repos/o/r/git/refs'));
  });

  test('getFile: 없으면 null, 있으면 base64 를 디코드한다', () async {
    final client = MockClient((req) async {
      if (req.url.queryParameters['ref'] == 'missing') return http.Response('not found', 404);
      return http.Response(
        jsonEncode({'sha': 'filesha', 'content': base64.encode(utf8.encode('안녕'))}),
        200,
      );
    });
    final api = GithubApi(token: 't', owner: 'o', repo: 'r', client: client);
    expect(await api.getFile('worklog/x.md', branch: 'missing'), isNull);
    final f = await api.getFile('worklog/x.md', branch: 'present');
    expect(f!.sha, 'filesha');
    expect(f.content, '안녕');
  });

  test('putFile: sha 가 있으면 함께 보낸다', () async {
    Map<String, dynamic>? sentBody;
    final client = MockClient((req) async {
      sentBody = jsonDecode(req.body) as Map<String, dynamic>;
      return http.Response(jsonEncode({'content': {}}), 200);
    });
    final api = GithubApi(token: 't', owner: 'o', repo: 'r', client: client);
    await api.putFile(path: 'a.md', branch: 'b', content: '내용', message: 'msg', sha: 'oldsha');
    expect(sentBody!['sha'], 'oldsha');
    expect(sentBody!['branch'], 'b');
    expect(utf8.decode(base64.decode(sentBody!['content'] as String)), '내용');
  });

  test('findOpenPull: 없으면 null, 있으면 첫 번째를 돌려준다', () async {
    final client = MockClient((req) async {
      if (req.url.queryParameters['head'] == 'o:empty-branch') {
        return http.Response(jsonEncode([]), 200);
      }
      return http.Response(
        jsonEncode([
          {'number': 7, 'html_url': 'https://github.com/o/r/pull/7'},
        ]),
        200,
      );
    });
    final api = GithubApi(token: 't', owner: 'o', repo: 'r', client: client);
    expect(await api.findOpenPull('empty-branch'), isNull);
    final pr = await api.findOpenPull('worklog/2026-01-01');
    expect(pr!.number, 7);
    expect(pr.htmlUrl, 'https://github.com/o/r/pull/7');
  });

  test('createPull', () async {
    final client = MockClient((req) async {
      final body = jsonDecode(req.body) as Map;
      expect(body['head'], 'worklog/2026-01-01');
      expect(body['base'], 'main');
      return http.Response(
        jsonEncode({'number': 9, 'html_url': 'https://github.com/o/r/pull/9'}),
        201,
      );
    });
    final api = GithubApi(token: 't', owner: 'o', repo: 'r', client: client);
    final pr = await api.createPull(
      headBranch: 'worklog/2026-01-01',
      baseBranch: 'main',
      title: 't',
      body: 'b',
    );
    expect(pr.number, 9);
  });

  test('오류 응답은 GithubException 으로 메시지를 담아 던진다', () async {
    final client = MockClient(
      (req) async => http.Response(jsonEncode({'message': 'Bad credentials'}), 401),
    );
    final api = GithubApi(token: 'bad', owner: 'o', repo: 'r', client: client);
    await expectLater(
      api.checkAccess(),
      throwsA(
        isA<GithubException>().having((e) => e.message, 'message', contains('Bad credentials')),
      ),
    );
  });
}
