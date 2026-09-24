import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../browser/session_store.dart';
import '../browser/sites.dart';
import '../core/settings_store.dart';
import '../services/service_catalog.dart';
import 'app_theme.dart';
import 'browser_screen.dart';
import 'remote_browser_screen.dart';

/// 한국 주요 서비스 목록. 브라우저로 되는 서비스는 탭해서 로그인해 둘 수 있다.
class ServicesScreen extends StatefulWidget {
  const ServicesScreen({super.key});

  @override
  State<ServicesScreen> createState() => _ServicesScreenState();
}

class _ServicesScreenState extends State<ServicesScreen> {
  String _query = '';
  bool _onlySupported = false;

  Future<void> _open(KService s) async {
    if (!s.supported) {
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(s.name),
          content: Text('브라우저로는 지원하지 않습니다.\n${s.note ?? '앱 전용 서비스입니다.'}'),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('확인'))],
        ),
      );
      return;
    }
    final settings = context.read<SettingsStore>();
    final url = s.login ?? s.home!;
    final message =
        '${s.name}에 로그인해 두면 이후 작업에서 바로 쓸 수 있습니다.'
        '${s.account != null ? ' (${s.account} 계정 하나로 관련 서비스가 함께 로그인됩니다)' : ''}';

    if (settings.runOnServer) {
      final client = settings.serverClient;
      if (client == null) return;
      try {
        await client.openUrl(url);
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
        return;
      }
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => RemoteBrowserScreen(client: client, title: s.name, message: message),
        ),
      );
      return;
    }

    final sessions = context.read<SiteSessionStore>();
    final site = siteById(s.id);
    final finalUrl = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => BrowserScreen(
          title: '${s.name} 로그인',
          initialUrl: site?.loginUrl ?? url,
          message: message,
          autoCloseOnLoginOf: site,
        ),
      ),
    );
    if (site != null && finalUrl != null && site.isLoggedInUrl(finalUrl)) {
      await sessions.markLoggedIn(site);
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalog = context.read<ServiceCatalog>();
    final q = _query.trim();
    final visible = catalog.services.where((s) {
      if (_onlySupported && !s.supported) return false;
      if (q.isEmpty) return true;
      return s.name.contains(q) || s.category.contains(q) || s.id.contains(q.toLowerCase());
    }).toList();
    final groups = <String, List<KService>>{};
    for (final s in visible) {
      (groups[s.category] ??= []).add(s);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('지원 서비스 (${catalog.supported.length}/${catalog.services.length})'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: '서비스·분류 검색 (예: 쇼핑, 기차, 네이버)',
              isDense: true,
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('브라우저로 되는 서비스만 보기'),
            value: _onlySupported,
            onChanged: (v) => setState(() => _onlySupported = v),
          ),
          Text(
            '탭하면 로그인 화면이 열립니다. 한 번 로그인해 두면 에이전트가 그 계정으로 작업합니다. '
            '결제·전송·예약 확정은 항상 승인 후에 진행됩니다.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          for (final e in groups.entries) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 16, 4, 4),
              child: Text(e.key, style: Theme.of(context).textTheme.titleSmall),
            ),
            for (final s in e.value)
              Card(
                margin: const EdgeInsets.symmetric(vertical: 3),
                child: ListTile(
                  title: Text(s.name),
                  subtitle: Text(
                    s.supported
                        ? (s.hint ?? s.note ?? Uri.parse(s.home!).host)
                        : (s.note ?? '앱 전용'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: _Badge(web: s.web),
                  onTap: () => _open(s),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.web});

  final String web;

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final (String label, Color bg, Color fg) = switch (web) {
      'web' => ('지원', t.accentSoft, t.accent),
      'partial' => ('일부', t.warningBg, t.warningInk),
      'excluded' => ('보안상 제외', t.line, t.muted),
      _ => ('앱 전용', t.line, t.muted),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppTokens.pill),
      ),
      child: Text(
        label,
        style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }
}
