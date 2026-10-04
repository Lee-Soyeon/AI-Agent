import '../github/github_store.dart';
import 'work_filter_models.dart';
import 'work_filter_store.dart';

class GithubUploadException implements Exception {
  GithubUploadException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// 업무 관련으로 분류된 항목을 하루 단위로 모아 브랜치 하나 + 파일 하나 + PR 하나로 올린다.
/// 같은 날짜에 다시 올리면 이미 있는 브랜치/PR 에 이어 붙인다.
class GithubUploadService {
  const GithubUploadService();

  String branchFor(String dayKey) => 'worklog/$dayKey';
  String pathFor(String dayKey) => 'worklog/$dayKey.md';

  String _sectionFor(SharedItem item) {
    final c = item.classification!;
    final time =
        '${item.receivedAt.hour.toString().padLeft(2, '0')}:'
        '${item.receivedAt.minute.toString().padLeft(2, '0')}';
    return '## $time · ${c.contentType}\n\n'
        '${c.summary}\n\n'
        '> 원문\n'
        '> ${item.rawText.replaceAll('\n', '\n> ')}\n';
  }

  /// [dayKey](YYYY-MM-DD)로 업무 관련인데 아직 안 올라간 항목을 모아 PR 하나로 올린다.
  /// 올릴 게 없으면 null, 성공하면 PR 주소를 돌려준다.
  Future<String?> uploadDay({
    required String dayKey,
    required List<SharedItem> items,
    required GithubStore github,
    required WorkFilterStore store,
  }) async {
    final pending =
        items
            .where(
              (i) =>
                  i.dayKey == dayKey &&
                  i.uploadStatus == UploadStatus.pending &&
                  i.classification?.isWork == true,
            )
            .toList()
          ..sort((a, b) => a.receivedAt.compareTo(b.receivedAt));
    if (pending.isEmpty) return null;
    if (!github.isConnected) {
      throw GithubUploadException('GitHub 이 연결되어 있지 않습니다. "GitHub 연결"에서 먼저 연결하세요.');
    }

    try {
      final api = github.createApi();
      final branch = branchFor(dayKey);
      final path = pathFor(dayKey);
      final base = await api.defaultBranch();
      await api.ensureBranch(branch, fromBranch: base);

      final existing = await api.getFile(path, branch: branch);
      final addition = pending.map(_sectionFor).join('\n---\n\n');
      final newContent = existing == null
          ? '# 업무 로그 $dayKey\n\n$addition'
          : '${existing.content.trimRight()}\n\n---\n\n$addition';

      await api.putFile(
        path: path,
        branch: branch,
        content: newContent,
        message: '업무 로그 $dayKey (+${pending.length}건)',
        sha: existing?.sha,
      );

      var pr = await api.findOpenPull(branch);
      pr ??= await api.createPull(
        headBranch: branch,
        baseBranch: base,
        title: '업무 로그 $dayKey',
        body: '에이닷/문자에서 업무 관련으로 분류된 내용을 모은 PR입니다. 앱에서 자동 생성되었습니다.',
      );

      for (final item in pending) {
        item.uploadStatus = UploadStatus.uploaded;
        item.prUrl = pr.htmlUrl;
        await store.upsert(item);
      }
      return pr.htmlUrl;
    } catch (e) {
      for (final item in pending) {
        item.uploadStatus = UploadStatus.failed;
        item.error = '$e';
        await store.upsert(item);
      }
      rethrow;
    }
  }
}
