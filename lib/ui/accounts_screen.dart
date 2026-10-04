import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../browser/session_store.dart';
import '../browser/sites.dart';
import '../core/settings_store.dart';
import '../google/google_auth.dart';
import '../google/writing_style.dart';
import '../services/service_catalog.dart';
import '../slack/slack_store.dart';
import 'app_theme.dart';
import 'browser_screen.dart';
import 'main_shell.dart';
import 'remote_browser_screen.dart';
import 'services_screen.dart';
import 'work_filter_screen.dart';
import 'writing_style_screen.dart';

/// 로그인 탭: 에이전트가 대신 쓸 서비스에 로그인하고 관리한다.
class AccountsScreen extends StatelessWidget {
  const AccountsScreen({super.key});

  Future<void> _login(BuildContext context, SiteConfig site) async {
    final sessions = context.read<SiteSessionStore>();
    final messenger = ScaffoldMessenger.of(context);
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
      messenger.showSnackBar(SnackBar(content: Text('${site.name} 로그인 완료')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsStore>();
    final sessions = context.watch<SiteSessionStore>();
    final google = context.watch<GoogleAuthService>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('로그인 관리')),
      body: ListView(
        padding: tabListPadding(context),
        children: [
          Text(
            settings.runOnServer
                ? '서버에서 실행 중입니다. 서버 브라우저에서 사용할 서비스에 한 번만 로그인해 두면 서버에 유지됩니다.'
                : '로그인은 직접 하고, 나머지는 에이전트가 합니다. 비밀번호는 앱이 저장하지 않습니다.',
            style: TextStyle(color: AppTokens.of(context).muted, fontSize: 13.5, height: 1.5),
          ),
          const SizedBox(height: 16),
          Text('연결된 서비스', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          if (settings.runOnServer) const _ServerBrowserCard(),
          if (!settings.runOnServer)
            for (final site in allSites)
              Card(
                child: ListTile(
                  leading: CircleAvatar(child: Icon(site.icon)),
                  title: Text(site.name),
                  subtitle: Text(sessions.isLoggedIn(site) ? '로그인됨' : '로그인이 필요합니다'),
                  trailing: sessions.isLoggedIn(site)
                      ? PopupMenuButton<String>(
                          onSelected: (v) =>
                              v == 'logout' ? sessions.logout(site) : _login(context, site),
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'login', child: Text('다시 로그인')),
                            PopupMenuItem(value: 'logout', child: Text('로그아웃')),
                          ],
                        )
                      : FilledButton.tonal(
                          onPressed: () => _login(context, site),
                          child: const Text('로그인'),
                        ),
                ),
              ),
          if (!settings.runOnServer) _GmailCard(google: google),
          _WorkFilterCard(slack: context.watch<SlackStore>()),
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
          Card(
            child: ListTile(
              leading: const Icon(Icons.swap_horiz),
              title: Text(settings.runOnServer ? '실행 위치: 서버' : '실행 위치: 이 폰'),
              subtitle: const Text('실행 위치는 모델 탭에서 바꿀 수 있어요'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.read<ShellTabs>().go(AppTab.model),
            ),
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

class _WorkFilterCard extends StatelessWidget {
  const _WorkFilterCard({required this.slack});

  final SlackStore slack;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.filter_alt_outlined)),
        title: const Text('업무 필터 → Slack'),
        subtitle: Text(
          slack.isConnected
              ? 'Slack 연결됨 · #${slack.channelName.isEmpty ? '채널 선택 필요' : slack.channelName}'
              : '에이닷/문자 공유 내용 중 업무 관련만 Slack으로 전달',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const WorkFilterScreen())),
      ),
    );
  }
}

class _GmailCard extends StatelessWidget {
  const _GmailCard({required this.google});

  final GoogleAuthService google;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: const CircleAvatar(child: Icon(Icons.mail)),
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
              child: Text(
                google.error!,
                style: TextStyle(color: AppTokens.of(context).errorInk, fontSize: 12),
              ),
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
