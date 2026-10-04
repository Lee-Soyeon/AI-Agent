import 'dart:convert';

import 'package:http/http.dart' as http;

class GithubException implements Exception {
  GithubException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => message;
}

class GithubFile {
  const GithubFile({required this.sha, required this.content});
  final String sha;
  final String content;
}

class GithubPullRequest {
  const GithubPullRequest({required this.number, required this.htmlUrl});
  final int number;
  final String htmlUrl;
}

/// GitHub REST API (Personal Access Token) 최소 클라이언트.
/// https://docs.github.com/rest — contents, git refs, pulls 만 쓴다.
class GithubApi {
  GithubApi({required this.token, required this.owner, required this.repo, http.Client? client})
    : _client = client ?? http.Client();

  final String token;
  final String owner;
  final String repo;
  final http.Client _client;

  static const _base = 'https://api.github.com';

  Map<String, String> get _headers => {
    'Authorization': 'Bearer $token',
    'Accept': 'application/vnd.github+json',
    'X-GitHub-Api-Version': '2022-11-28',
  };

  Future<dynamic> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    final uri = Uri.parse('$_base$path').replace(queryParameters: query);
    final headers = {..._headers, if (body != null) 'content-type': 'application/json'};
    final http.Response res;
    switch (method) {
      case 'GET':
        res = await _client.get(uri, headers: headers).timeout(const Duration(seconds: 20));
      case 'POST':
        res = await _client
            .post(uri, headers: headers, body: jsonEncode(body))
            .timeout(const Duration(seconds: 20));
      case 'PUT':
        res = await _client
            .put(uri, headers: headers, body: jsonEncode(body))
            .timeout(const Duration(seconds: 20));
      default:
        throw ArgumentError('unsupported method $method');
    }
    final text = utf8.decode(res.bodyBytes);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      var msg = text;
      try {
        msg = (jsonDecode(text) as Map)['message'] as String? ?? text;
      } catch (_) {}
      throw GithubException('GitHub API 오류 (${res.statusCode}): $msg', statusCode: res.statusCode);
    }
    return text.isEmpty ? null : jsonDecode(text);
  }

  Future<String> defaultBranch() async {
    final j = await _request('GET', '/repos/$owner/$repo') as Map;
    return j['default_branch'] as String;
  }

  Future<String> _branchHeadSha(String branch) async {
    final j = await _request('GET', '/repos/$owner/$repo/git/ref/heads/$branch') as Map;
    return (j['object'] as Map)['sha'] as String;
  }

  /// [branch] 가 없으면 [fromBranch] 최신 커밋에서 새로 만든다. 돌려주는 값은 "새로 만들었는지".
  Future<bool> ensureBranch(String branch, {required String fromBranch}) async {
    try {
      await _branchHeadSha(branch);
      return false;
    } on GithubException catch (e) {
      if (e.statusCode != 404) rethrow;
    }
    final sha = await _branchHeadSha(fromBranch);
    await _request('POST', '/repos/$owner/$repo/git/refs', body: {'ref': 'refs/heads/$branch', 'sha': sha});
    return true;
  }

  /// [branch] 에 그 파일이 있으면 내용(sha 포함)을 돌려준다. 없으면 null.
  Future<GithubFile?> getFile(String path, {required String branch}) async {
    try {
      final j =
          await _request('GET', '/repos/$owner/$repo/contents/$path', query: {'ref': branch}) as Map;
      return GithubFile(sha: j['sha'] as String, content: decodeBase64(j['content'] as String));
    } on GithubException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  /// 파일을 만들거나 덮어쓴다. 수정이면(이미 있던 파일) [sha] 가 필요하다.
  Future<void> putFile({
    required String path,
    required String branch,
    required String content,
    required String message,
    String? sha,
  }) => _request(
    'PUT',
    '/repos/$owner/$repo/contents/$path',
    body: {
      'message': message,
      'content': base64.encode(utf8.encode(content)),
      'branch': branch,
      if (sha != null) 'sha': sha,
    },
  );

  /// 그 head 브랜치로 이미 열려 있는 PR 이 있으면 돌려준다 (없으면 null).
  Future<GithubPullRequest?> findOpenPull(String headBranch) async {
    final list =
        await _request(
              'GET',
              '/repos/$owner/$repo/pulls',
              query: {'state': 'open', 'head': '$owner:$headBranch'},
            )
            as List;
    if (list.isEmpty) return null;
    final m = (list.first as Map).cast<String, dynamic>();
    return GithubPullRequest(number: m['number'] as int, htmlUrl: m['html_url'] as String);
  }

  Future<GithubPullRequest> createPull({
    required String headBranch,
    required String baseBranch,
    required String title,
    required String body,
  }) async {
    final j =
        await _request(
              'POST',
              '/repos/$owner/$repo/pulls',
              body: {'title': title, 'head': headBranch, 'base': baseBranch, 'body': body},
            )
            as Map;
    return GithubPullRequest(number: j['number'] as int, htmlUrl: j['html_url'] as String);
  }

  /// 토큰이 유효하고 이 저장소에 접근 가능한지 확인한다.
  Future<void> checkAccess() async {
    await _request('GET', '/repos/$owner/$repo');
  }

  static String decodeBase64(String s) =>
      utf8.decode(base64.decode(s.replaceAll('\n', '')), allowMalformed: true);
}
