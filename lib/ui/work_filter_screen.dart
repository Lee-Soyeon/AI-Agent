import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/settings_store.dart';
import '../slack/slack_api.dart';
import '../slack/slack_oauth_service.dart';
import '../slack/slack_store.dart';
import '../workfilter/work_filter_models.dart';
import '../workfilter/work_filter_service.dart';
import '../workfilter/work_filter_store.dart';
import 'app_theme.dart';
import 'main_shell.dart';

/// 업무 필터: 에이닷/문자에서 공유된 내용을 LLM 이 분류해 업무 관련만 Slack 으로 보낸다.
class WorkFilterScreen extends StatefulWidget {
  const WorkFilterScreen({super.key});

  @override
  State<WorkFilterScreen> createState() => _WorkFilterScreenState();
}

class _WorkFilterScreenState extends State<WorkFilterScreen> {
  final _tokenCtrl = TextEditingController();
  final _testCtrl = TextEditingController();
  final _service = const WorkFilterService();
  bool _connecting = false;
  bool _testing = false;
  String? _connectError;
  bool _showManualToken = !SlackOAuthService.isConfigured;

  @override
  void dispose() {
    _tokenCtrl.dispose();
    _testCtrl.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final token = _tokenCtrl.text.trim();
    if (token.isEmpty) return;
    setState(() {
      _connecting = true;
      _connectError = null;
    });
    try {
      await context.read<SlackStore>().connect(token);
      _tokenCtrl.clear();
    } catch (e) {
      _connectError = '$e';
    }
    if (mounted) setState(() => _connecting = false);
  }

  Future<void> _connectOAuth() async {
    final service = SlackOAuthService();
    final messenger = ScaffoldMessenger.of(context);
    SlackOAuthStart start;
    try {
      start = await service.start();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
      return;
    }
    final opened = await launchUrl(Uri.parse(start.authorizeUrl), mode: LaunchMode.externalApplication);
    if (!opened) {
      messenger.showSnackBar(const SnackBar(content: Text('브라우저를 열지 못했습니다.')));
      return;
    }
    if (!mounted) return;
    final result = await showDialog<SlackOAuthResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _SlackOAuthWaitingDialog(service: service, state: start.state),
    );
    if (result != null && mounted) {
      await context.read<SlackStore>().connectWithOAuth(result);
    }
  }

  Future<void> _pickChannel() async {
    final slack = context.read<SlackStore>();
    final future = slack.createApi().listChannels();
    final picked = await showModalBottomSheet<SlackChannel>(
      context: context,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (context, scroll) => FutureBuilder<List<SlackChannel>>(
          future: future,
          builder: (context, snap) {
            if (snap.hasError) {
              return Padding(
                padding: const EdgeInsets.all(24),
                child: Text('채널 목록을 불러오지 못했습니다.\n${snap.error}'),
              );
            }
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final channels = snap.data!;
            return ListView(
              controller: scroll,
              children: [
                ListTile(title: Text('채널 ${channels.length}개 — 보낼 채널을 고르세요')),
                for (final c in channels)
                  ListTile(
                    leading: Icon(c.isPrivate ? Icons.lock_outline : Icons.tag),
                    title: Text(c.name),
                    trailing: c.id == slack.channelId ? const Icon(Icons.check) : null,
                    onTap: () => Navigator.pop(context, c),
                  ),
              ],
            );
          },
        ),
      ),
    );
    if (picked != null && mounted) await context.read<SlackStore>().setChannel(picked);
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
      slack: context.read<SlackStore>(),
      store: context.read<WorkFilterStore>(),
    );
    _testCtrl.clear();
    if (mounted) setState(() => _testing = false);
  }

  @override
  Widget build(BuildContext context) {
    final slack = context.watch<SlackStore>();
    final items = context.watch<WorkFilterStore>().items;
    final t = AppTokens.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('업무 필터 → Slack')),
      body: ListView(
        padding: tabListPadding(context),
        children: [
          Text(
            '에이닷/문자 공유 시트에서 이 앱으로 보낸 내용을 LLM 이 업무 관련인지 판단해, '
            '업무 관련인 것만 Slack 채널로 전달합니다. iOS 공유 시트 연동은 한 번 수동 설정이 필요합니다 '
            '(docs/work-filter-slack-setup.md).',
            style: TextStyle(color: t.muted, fontSize: 13.5, height: 1.5),
          ),
          const SizedBox(height: 16),
          Text('Slack 연결', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: slack.isConnected
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const CircleAvatar(child: Icon(Icons.tag)),
                          title: Text(slack.teamName.isEmpty ? 'Slack 연결됨' : slack.teamName),
                          subtitle: Text(
                            slack.channelName.isEmpty ? '채널을 선택하세요' : '#${slack.channelName}',
                          ),
                          trailing: PopupMenuButton<String>(
                            onSelected: (_) => slack.disconnect(),
                            itemBuilder: (_) => const [
                              PopupMenuItem(value: 'disconnect', child: Text('연결 해제')),
                            ],
                          ),
                        ),
                        OutlinedButton(onPressed: _pickChannel, child: const Text('보낼 채널 선택')),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (SlackOAuthService.isConfigured) ...[
                          FilledButton.icon(
                            onPressed: _connectOAuth,
                            icon: const Icon(Icons.link),
                            label: const Text('Slack 워크스페이스 연동'),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '클릭하면 브라우저에서 Slack 워크스페이스를 고르고 승인하면 됩니다. '
                            'Slack App을 직접 만들 필요가 없습니다.',
                            style: TextStyle(color: t.muted, fontSize: 12),
                          ),
                          const SizedBox(height: 4),
                          TextButton(
                            onPressed: () => setState(() => _showManualToken = !_showManualToken),
                            child: Text(_showManualToken ? '직접 Bot Token 입력 접기' : '직접 Bot Token 입력 (고급)'),
                          ),
                        ],
                        if (_showManualToken) ...[
                          const SizedBox(height: 4),
                          TextField(
                            controller: _tokenCtrl,
                            obscureText: true,
                            autocorrect: false,
                            enableSuggestions: false,
                            decoration: const InputDecoration(
                              labelText: 'Slack Bot Token',
                              hintText: 'xoxb-...',
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
                            'Slack 앱을 만들어 chat:write, channels:read(비공개 채널도 쓰려면 groups:read) '
                            '권한을 추가하고 워크스페이스에 설치하면 Bot User OAuth Token(xoxb-...)을 받습니다.',
                            style: TextStyle(color: t.muted, fontSize: 12),
                          ),
                        ],
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
            decoration: const InputDecoration(hintText: '여기에 통화 요약/문자 내용을 붙여넣으세요', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 8),
          FilledButton.tonal(
            onPressed: _testing ? null : _runTest,
            child: Text(_testing ? '처리 중…' : '분류 + 전송 테스트'),
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

/// Slack 승인을 기다리는 동안 보여주는 창. ChatGPT 기기 코드 로그인과 같은 "브라우저에서 승인 →
/// 앱은 주기적으로 확인" 패턴이라 별도 딥링크 설정이 필요 없다.
class _SlackOAuthWaitingDialog extends StatefulWidget {
  const _SlackOAuthWaitingDialog({required this.service, required this.state});

  final SlackOAuthService service;
  final String state;

  @override
  State<_SlackOAuthWaitingDialog> createState() => _SlackOAuthWaitingDialogState();
}

class _SlackOAuthWaitingDialogState extends State<_SlackOAuthWaitingDialog> {
  String? _error;
  bool _cancelled = false;

  @override
  void initState() {
    super.initState();
    _wait();
  }

  Future<void> _wait() async {
    try {
      final result = await widget.service.waitForResult(
        widget.state,
        isCancelled: () => _cancelled || !mounted,
      );
      if (mounted) Navigator.of(context).pop(result);
    } catch (e) {
      if (mounted && !_cancelled) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    return AlertDialog(
      title: const Text('Slack 연동'),
      content: error != null
          ? Text(error, style: TextStyle(color: Theme.of(context).colorScheme.error))
          : const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('브라우저에서 워크스페이스를 선택하고 "허용"을 누른 뒤 앱으로 돌아오세요.'),
                SizedBox(height: 16),
                LinearProgressIndicator(),
              ],
            ),
      actions: [
        TextButton(
          onPressed: () {
            _cancelled = true;
            Navigator.of(context).pop();
          },
          child: const Text('취소'),
        ),
        if (error != null)
          FilledButton(
            onPressed: () {
              setState(() => _error = null);
              _wait();
            },
            child: const Text('다시 확인'),
          ),
      ],
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
    final slackLabel = switch (item.slackStatus) {
      SlackSendStatus.sent => 'Slack 전송됨',
      SlackSendStatus.failed => 'Slack 전송 실패',
      SlackSendStatus.skippedNotWork => 'Slack 전송 안 함(업무 아님)',
      SlackSendStatus.notSent => c?.isWork == true ? 'Slack 미연결' : '',
    };
    return Card(
      child: ListTile(
        title: Text(c?.summary.isNotEmpty == true ? c!.summary : item.preview),
        subtitle: Text(
          [
            if (item.error != null) item.error!,
            if (slackLabel.isNotEmpty) slackLabel,
          ].join(' · '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Chip(label: Text(label), backgroundColor: color.withValues(alpha: 0.15)),
      ),
    );
  }
}
