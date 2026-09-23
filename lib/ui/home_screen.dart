import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../agent/agent_controller.dart';
import '../agent/agent_models.dart';
import '../browser/session_store.dart';
import '../browser/sites.dart';
import '../core/settings_store.dart';
import '../google/google_auth.dart';
import '../openai/chatgpt_auth.dart';
import 'browser_screen.dart';
import 'settings_screen.dart';
import 'task_screen.dart';

const _examples = [
  '쿠팡에서 삼다수 2L 12개 로켓배송 제일 싼 걸 장바구니에 담고, 결제 전에 나한테 승인 받아줘',
  '쿠팡 장바구니에 뭐가 들어있는지 알려줘',
  'Gmail 에서 안 읽은 메일 5개 요약해줘',
  'Gmail 에서 가장 최근 메일에 "확인했습니다, 감사합니다" 라고 답장 써서 승인 받고 보내줘',
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
              title: Text(settings.vendor.label),
              subtitle: Text(
                settings.isConfigured
                    ? '모델: ${settings.model(settings.vendor)}'
                    : 'API 키가 설정되지 않았습니다',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: _openSettings,
            ),
          ),
          const SizedBox(height: 16),
          Text('연결된 서비스', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
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
          _GmailCard(google: google),
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
