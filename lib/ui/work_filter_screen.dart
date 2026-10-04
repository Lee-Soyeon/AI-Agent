import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/settings_store.dart';
import '../github/github_store.dart';
import '../workfilter/github_upload_service.dart';
import '../workfilter/work_filter_models.dart';
import '../workfilter/work_filter_service.dart';
import '../workfilter/work_filter_store.dart';
import 'app_theme.dart';
import 'main_shell.dart';

String _todayKey() {
  final now = DateTime.now();
  return '${now.year.toString().padLeft(4, '0')}-'
      '${now.month.toString().padLeft(2, '0')}-'
      '${now.day.toString().padLeft(2, '0')}';
}

/// 업무 필터: 에이닷/문자에서 공유된 내용을 LLM 이 분류해, 업무 관련인 것만 하루치씩 모아
/// GitHub PR 로 올린다.
class WorkFilterScreen extends StatefulWidget {
  const WorkFilterScreen({super.key});

  @override
  State<WorkFilterScreen> createState() => _WorkFilterScreenState();
}

class _WorkFilterScreenState extends State<WorkFilterScreen> {
  final _tokenCtrl = TextEditingController();
  final _ownerCtrl = TextEditingController();
  final _repoCtrl = TextEditingController();
  final _testCtrl = TextEditingController();
  final _service = const WorkFilterService();
  final _uploadService = const GithubUploadService();
  bool _connecting = false;
  bool _testing = false;
  bool _uploading = false;
  String? _connectError;

  @override
  void dispose() {
    _tokenCtrl.dispose();
    _ownerCtrl.dispose();
    _repoCtrl.dispose();
    _testCtrl.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final token = _tokenCtrl.text.trim();
    final owner = _ownerCtrl.text.trim();
    final repo = _repoCtrl.text.trim();
    if (token.isEmpty || owner.isEmpty || repo.isEmpty) return;
    setState(() {
      _connecting = true;
      _connectError = null;
    });
    try {
      await context.read<GithubStore>().connect(token: token, owner: owner, repo: repo);
      _tokenCtrl.clear();
    } catch (e) {
      _connectError = '$e';
    }
    if (mounted) setState(() => _connecting = false);
  }

  Future<void> _runTest() async {
    final text = _testCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _testing = true);
    final item = SharedItem(
      id: 'manual_${DateTime.now().microsecondsSinceEpoch}',
      receivedAt: DateTime.now(),
      rawText: text,
    );
    await _service.process(
      item: item,
      settings: context.read<SettingsStore>(),
      store: context.read<WorkFilterStore>(),
    );
    _testCtrl.clear();
    if (mounted) setState(() => _testing = false);
  }

  Future<void> _uploadToday() async {
    setState(() => _uploading = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final store = context.read<WorkFilterStore>();
      final url = await _uploadService.uploadDay(
        dayKey: _todayKey(),
        items: store.items,
        github: context.read<GithubStore>(),
        store: store,
      );
      messenger.showSnackBar(
        SnackBar(content: Text(url == null ? '오늘 올릴 업무 내용이 없습니다.' : 'PR 생성/업데이트됨: $url')),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
    if (mounted) setState(() => _uploading = false);
  }

  @override
  Widget build(BuildContext context) {
    final github = context.watch<GithubStore>();
    final items = context.watch<WorkFilterStore>().items;
    final pendingToday = items
        .where((i) => i.dayKey == _todayKey() && i.uploadStatus == UploadStatus.pending)
        .length;
    final t = AppTokens.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('업무 필터 → GitHub')),
      body: ListView(
        padding: tabListPadding(context),
        children: [
          Text(
            '에이닷/문자 공유 시트에서 이 앱으로 보낸 내용을 LLM 이 업무 관련인지 판단합니다. '
            '업무 관련인 내용은 하루치씩 모아 GitHub 저장소에 PR 하나로 올립니다. '
            'iOS 공유 시트 연동은 한 번 수동 설정이 필요합니다 (docs/work-filter-github-setup.md).',
            style: TextStyle(color: t.muted, fontSize: 13.5, height: 1.5),
          ),
          const SizedBox(height: 16),
          Text('GitHub 연결', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: github.isConnected
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const CircleAvatar(child: Icon(Icons.code)),
                          title: Text('${github.owner}/${github.repo}'),
                          subtitle: Text('오늘 올릴 업무 내용 $pendingToday건'),
                          trailing: PopupMenuButton<String>(
                            onSelected: (_) => github.disconnect(),
                            itemBuilder: (_) => const [
                              PopupMenuItem(value: 'disconnect', child: Text('연결 해제')),
                            ],
                          ),
                        ),
                        FilledButton.icon(
                          onPressed: _uploading ? null : _uploadToday,
                          icon: const Icon(Icons.upload),
                          label: Text(_uploading ? '올리는 중…' : '오늘 분 GitHub PR로 올리기'),
                        ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: _ownerCtrl,
                          autocorrect: false,
                          decoration: const InputDecoration(
                            labelText: '저장소 소유자 (owner)',
                            hintText: '예: booboobook',
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _repoCtrl,
                          autocorrect: false,
                          decoration: const InputDecoration(
                            labelText: '저장소 이름 (repo)',
                            hintText: '예: aidol-ir',
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _tokenCtrl,
                          obscureText: true,
                          autocorrect: false,
                          enableSuggestions: false,
                          decoration: const InputDecoration(
                            labelText: 'Personal Access Token',
                            hintText: 'github_pat_... 또는 ghp_...',
                          ),
                        ),
                        const SizedBox(height: 8),
                        FilledButton(
                          onPressed: _connecting ? null : _connect,
                          child: Text(_connecting ? '연결 중…' : '연결'),
                        ),
                        if (_connectError != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(_connectError!, style: TextStyle(color: t.errorInk)),
                          ),
                        const SizedBox(height: 8),
                        Text(
                          'GitHub → Settings → Developer settings → Fine-grained personal access token '
                          '에서 이 저장소만 선택해 Contents(Read and write), Pull requests(Read and write) '
                          '권한으로 발급하세요.',
                          style: TextStyle(color: t.muted, fontSize: 12),
                        ),
                      ],
                    ),
            ),
          ),
          const Divider(height: 32),
          Text('텍스트로 테스트', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            '에이닷 통화 요약이나 문자 내용을 복사해 붙여넣고 테스트할 수 있습니다 (공유 시트 설정 없이도 동작).',
            style: TextStyle(color: t.muted, fontSize: 12.5),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _testCtrl,
            minLines: 3,
            maxLines: 8,
            decoration: const InputDecoration(
              hintText: '여기에 통화 요약/문자 내용을 붙여넣으세요',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.tonal(
            onPressed: _testing ? null : _runTest,
            child: Text(_testing ? '처리 중…' : '분류 테스트'),
          ),
          const Divider(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('처리 기록', style: Theme.of(context).textTheme.titleMedium),
              if (items.isNotEmpty)
                TextButton(
                  onPressed: () => context.read<WorkFilterStore>().clear(),
                  child: const Text('기록 지우기'),
                ),
            ],
          ),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text('아직 처리한 내용이 없습니다.', style: TextStyle(color: t.muted)),
            ),
          for (final item in items) _ItemCard(item: item),
        ],
      ),
    );
  }
}

class _ItemCard extends StatelessWidget {
  const _ItemCard({required this.item});

  final SharedItem item;

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final c = item.classification;
    final (label, color) = switch (item.status) {
      ShareItemStatus.processing => ('처리 중…', t.muted),
      ShareItemStatus.error => ('오류', t.errorInk),
      ShareItemStatus.done when c == null => ('완료', t.muted),
      ShareItemStatus.done => c!.isWork ? ('업무 · ${c.contentType}', t.accent) : ('개인/기타', t.muted),
    };
    final uploadLabel = switch (item.uploadStatus) {
      UploadStatus.uploaded => 'GitHub PR 로 올림',
      UploadStatus.failed => 'GitHub 업로드 실패',
      UploadStatus.skippedNotWork => '업무 아님 (올리지 않음)',
      UploadStatus.pending => c?.isWork == true ? '오늘 분 업로드 대기' : '',
    };
    return Card(
      child: ListTile(
        title: Text(c?.summary.isNotEmpty == true ? c!.summary : item.preview),
        subtitle: Text(
          [
            if (item.error != null) item.error!,
            if (uploadLabel.isNotEmpty) uploadLabel,
          ].join(' · '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Chip(label: Text(label), backgroundColor: color.withValues(alpha: 0.15)),
      ),
    );
  }
}
