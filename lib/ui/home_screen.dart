import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../agent/agent_controller.dart';
import '../agent/agent_models.dart';
import '../browser/session_store.dart';
import '../browser/sites.dart';
import '../core/settings_store.dart';
import '../google/google_auth.dart';
import '../google/writing_style.dart';
import '../openai/chatgpt_auth.dart';
import '../services/service_catalog.dart';
import 'browser_screen.dart';
import 'remote_browser_screen.dart';
import 'services_screen.dart';
import 'settings_screen.dart';
import 'task_screen.dart';
import 'writing_style_screen.dart';

const _examples = [
  '쿠팡에서 삼다수 2L 12개 로켓배송 제일 싼 걸 장바구니에 담고, 결제 전에 나한테 승인 받아줘',
  '쿠팡 장바구니에 뭐가 들어있는지 알려줘',
  'Gmail 에서 안 읽은 메일 5개 요약해줘',
  'Gmail 에서 가장 최근 메일에 "확인했습니다, 감사합니다" 라고 답장 써서 승인 받고 보내줘',
  '안 읽은 메일 중 답장이 필요한 것에 평소 내 말투로 답장 초안 써줘',
  '이번 주 토요일 저녁 7시 강남역 근처 4인 파스타집 네이버 예약 가능한 곳 찾아줘',
  '다음 주 금요일 서울→부산 KTX 오후 6시 이후 좌석 있는지 봐줘',
  '오늘 CGV 용산 저녁 상영시간표 알려줘',
  'G마켓·11번가·쿠팡에서 에어팟 프로 최저가 비교해줘',
];

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _task = TextEditingController();

  @override
  void dispose() {
    _task.dispose();
    super.dispose();
  }

  Future<void> _login(SiteConfig site) async {
    final sessions = context.read<SiteSessionStore>();
    final url = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => BrowserScreen(
          title: '${site.name} 로그인',
          initialUrl: site.loginUrl,
          message: '${site.name}에 로그인해 주세요. 로그인이 끝나면 자동으로 닫히고, 이후 작업은 백그라운드에서 진행됩니다.',
          autoCloseOnLoginOf: site,
        ),
      ),
    );
    if (url != null && site.isLoggedInUrl(url)) {
      await sessions.markLoggedIn(site);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${site.name} 로그인 완료')));
      }
    }
  }

  Future<void> _start() async {
    final text = _task.text.trim();
    if (text.isEmpty) return;
    final settings = context.read<SettingsStore>();
    if (!settings.isConfigured) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('먼저 설정에서 LLM API 키를 입력하세요.'),
          action: SnackBarAction(label: '설정', onPressed: _openSettings),
        ),
      );
      return;
    }
    final agent = context.read<AgentController>();
    FocusScope.of(context).unfocus();
    _task.clear();
    // 작업은 백그라운드에서 돌고, 화면은 진행 상황을 보여준다.
    agent.startTask(text);
    _openTask();
  }

  void _openTask() =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TaskScreen()));

  void _openSettings() =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsStore>();
    final sessions = context.watch<SiteSessionStore>();
    final agent = context.watch<AgentController>();
    final google = context.watch<GoogleAuthService>();
    context.watch<ChatGptAuth>(); // ChatGPT 로그인 상태가 바뀌면 LLM 카드를 갱신
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Agent'),
        actions: [IconButton(icon: const Icon(Icons.settings), onPressed: _openSettings)],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (agent.status != AgentStatus.idle) _ActiveTaskBanner(agent: agent, onTap: _openTask),
          Card(
            child: ListTile(
              leading: const Icon(Icons.auto_awesome),
              title: Text(settings.runOnServer ? '서버에서 실행 (백그라운드)' : settings.vendor.label),
              subtitle: Text(
                settings.isConfigured
                    ? (settings.runOnServer
                          ? settings.serverUrl
                          : '모델: ${settings.model(settings.vendor)}')
                    : settings.runOnServer
                    ? '서버 주소와 토큰을 설정하세요'
                    : 'API 키가 설정되지 않았습니다',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: _openSettings,
            ),
          ),
          const SizedBox(height: 16),
          Text('연결된 서비스', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          if (settings.runOnServer) const _ServerBrowserCard(),
          if (!settings.runOnServer)
            for (final site in allSites)
              Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: site.color,
                    foregroundColor: Colors.white,
                    child: Icon(site.icon),
                  ),
                  title: Text(site.name),
                  subtitle: Text(sessions.isLoggedIn(site) ? '로그인됨' : '로그인이 필요합니다'),
                  trailing: sessions.isLoggedIn(site)
                      ? PopupMenuButton<String>(
                          onSelected: (v) => v == 'logout' ? sessions.logout(site) : _login(site),
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'login', child: Text('다시 로그인')),
                            PopupMenuItem(value: 'logout', child: Text('로그아웃')),
                          ],
                        )
                      : FilledButton.tonal(onPressed: () => _login(site), child: const Text('로그인')),
                ),
              ),
          if (!settings.runOnServer) _GmailCard(google: google),
          Card(
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.apps)),
              title: const Text('한국 주요 서비스'),
              subtitle: Text(
                '브라우저로 되는 ${context.read<ServiceCatalog>().supported.length}개 서비스 — 탭해서 로그인',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () =>
                  Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => const ServicesScreen())),
            ),
          ),
          const SizedBox(height: 16),
          Text('무엇을 해드릴까요?', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(
            controller: _task,
            minLines: 3,
            maxLines: 6,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: '예) 쿠팡에서 휴지 30롤 담아줘',
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: agent.isBusy ? null : _start,
            icon: const Icon(Icons.play_arrow),
            label: Text(agent.isBusy ? '작업 진행 중…' : '실행'),
          ),
          const SizedBox(height: 16),
          Text('예시', style: theme.textTheme.labelLarge),
          const SizedBox(height: 4),
          for (final e in _examples)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.lightbulb_outline, size: 20),
              title: Text(e),
              onTap: () => _task.text = e,
            ),
        ],
      ),
    );
  }
}

/// 서버 모드: 서버 브라우저에 사이트를 열어 사용자가 직접 로그인한다 (한 번만 하면 서버에 유지됨).
class _ServerBrowserCard extends StatelessWidget {
  const _ServerBrowserCard();

  static const _presets = {
    '쿠팡': 'https://login.coupang.com/login/login.pang',
    '네이버': 'https://nid.naver.com/nidlogin.login',
    'Gmail': 'https://accounts.google.com/ServiceLogin?service=mail',
    '코레일': 'https://www.korail.com/ticket/login',
  };

  Future<void> _open(BuildContext context, String url) async {
    final client = context.read<SettingsStore>().serverClient;
    if (client == null) return;
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await client.openUrl(url);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
      return;
    }
    await nav.push<void>(
      MaterialPageRoute(
        builder: (_) => RemoteBrowserScreen(
          client: client,
          title: '서버 브라우저',
          message:
              '여기서 로그인하면 서버에 저장되어, 이후 작업은 백그라운드에서 진행됩니다. '
              '"로그인 상태 유지"를 체크하세요.',
        ),
      ),
    );
  }

  Future<void> _custom(BuildContext context) async {
    final c = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('로그인할 사이트 주소'),
        content: TextField(
          controller: c,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(hintText: 'https://'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
          FilledButton(
            onPressed: () => Navigator.pop(context, c.text.trim()),
            child: const Text('열기'),
          ),
        ],
      ),
    );
    if (url == null || url.isEmpty || !context.mounted) return;
    await _open(context, url.startsWith('http') ? url : 'https://$url');
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(child: Icon(Icons.cloud)),
              title: Text('서버 브라우저'),
              subtitle: Text('사용할 서비스에 한 번만 로그인해 두세요. 어떤 웹 서비스든 됩니다.'),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final e in _presets.entries)
                  ActionChip(label: Text('${e.key} 로그인'), onPressed: () => _open(context, e.value)),
                ActionChip(
                  avatar: const Icon(Icons.add, size: 18),
                  label: const Text('다른 사이트'),
                  onPressed: () => _custom(context),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _GmailCard extends StatelessWidget {
  const _GmailCard({required this.google});

  final GoogleAuthService google;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: const CircleAvatar(
              backgroundColor: Color(0xFF1A73E8),
              foregroundColor: Colors.white,
              child: Icon(Icons.mail),
            ),
            title: const Text('Gmail'),
            subtitle: Text(
              google.isSignedIn ? '${google.email} · Gmail API 연결됨' : 'Google 계정 연결이 필요합니다',
            ),
            trailing: google.busy
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : google.isSignedIn
                ? PopupMenuButton<String>(
                    onSelected: (_) => google.signOut(),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'logout', child: Text('연결 해제 (권한 철회)')),
                    ],
                  )
                : FilledButton.tonal(onPressed: google.signIn, child: const Text('Google 계정 연결')),
          ),
          if (google.error != null && !google.isSignedIn)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(google.error!, style: TextStyle(color: scheme.error, fontSize: 12)),
            ),
          if (google.isSignedIn)
            Builder(
              builder: (context) {
                final style = context.watch<WritingStyleStore>();
                final p = style.profile;
                return ListTile(
                  leading: const Icon(Icons.draw_outlined),
                  title: const Text('내 메일 말투'),
                  subtitle: Text(
                    style.busy
                        ? (style.progress ?? '학습 중…')
                        : p == null
                        ? '보낸 메일로 학습하면 내가 쓴 것처럼 작성합니다'
                        : '보낸 메일 ${p.analyzedCount}통으로 학습됨',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () =>
                      Navigator.of(context)
                          .push(MaterialPageRoute(builder: (_) => const WritingStyleScreen())),
                );
              },
            ),
        ],
      ),
    );
  }
}

class _ActiveTaskBanner extends StatelessWidget {
  const _ActiveTaskBanner({required this.agent, required this.onTap});

  final AgentController agent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final needsYou = agent.pendingApproval != null || agent.pendingQuestion != null;
    return Card(
      color: needsYou ? scheme.errorContainer : scheme.primaryContainer,
      child: ListTile(
        leading: agent.isBusy && !needsYou
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(needsYou ? Icons.notification_important : Icons.task_alt),
        title: Text(needsYou ? '승인/답변이 필요합니다' : statusLabel(agent.status)),
        subtitle: const Text('탭해서 진행 상황 보기'),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

String statusLabel(AgentStatus s) => switch (s) {
  AgentStatus.idle => '대기 중',
  AgentStatus.running => '에이전트가 작업 중입니다',
  AgentStatus.waitingApproval => '승인을 기다리는 중',
  AgentStatus.waitingUser => '사용자 입력을 기다리는 중',
  AgentStatus.finished => '작업 완료',
  AgentStatus.failed => '작업 실패',
  AgentStatus.cancelled => '작업 취소됨',
};
