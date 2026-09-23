import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../browser/sites.dart';
import '../browser/web_settings.dart';

/// 사용자가 직접 조작하는 보이는 브라우저. 로그인하거나 에이전트가 도움을 요청했을 때 뜬다.
/// 닫힐 때 마지막 URL 을 돌려준다.
class BrowserScreen extends StatefulWidget {
  const BrowserScreen({
    super.key,
    required this.title,
    required this.initialUrl,
    this.message,
    this.autoCloseOnLoginOf,
  });

  final String title;
  final String initialUrl;
  final String? message;

  /// 지정하면 해당 사이트의 로그인 완료 URL 에 도달했을 때 자동으로 닫힌다.
  final SiteConfig? autoCloseOnLoginOf;

  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen> {
  InAppWebViewController? _controller;
  String? _url;
  double _progress = 0;
  bool _closing = false;

  void _close() {
    if (_closing) return;
    _closing = true;
    Navigator.of(context).pop(_url ?? widget.initialUrl);
  }

  void _onUrl(String url) {
    setState(() => _url = url);
    final site = widget.autoCloseOnLoginOf;
    if (site != null && site.isLoggedInUrl(url)) {
      // 로그인 직후 리다이렉트가 끝날 시간을 조금 준다.
      Future<void>.delayed(const Duration(milliseconds: 800), () {
        if (mounted) _close();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final c = _controller;
        if (c != null && await c.canGoBack()) {
          await c.goBack();
        } else {
          _close();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.title),
              if (_url != null)
                Text(
                  Uri.tryParse(_url!)?.host ?? '',
                  style: Theme.of(context).textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: '새로고침',
              icon: const Icon(Icons.refresh),
              onPressed: () => _controller?.reload(),
            ),
            FilledButton.icon(
              onPressed: _close,
              icon: const Icon(Icons.check),
              label: const Text('완료'),
            ),
            const SizedBox(width: 8),
          ],
          bottom: _progress < 1
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(2),
                  child: LinearProgressIndicator(value: _progress, minHeight: 2),
                )
              : null,
        ),
        body: Column(
          children: [
            if (widget.message != null)
              Material(
                color: scheme.secondaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: scheme.onSecondaryContainer),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${widget.message}\n끝나면 오른쪽 위 [완료]를 눌러 주세요.',
                          style: TextStyle(color: scheme.onSecondaryContainer),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: InAppWebView(
                initialUrlRequest: URLRequest(url: WebUri(widget.initialUrl)),
                initialSettings: buildWebSettings(),
                onWebViewCreated: (c) => _controller = c,
                onProgressChanged: (c, p) => setState(() => _progress = p / 100),
                onUpdateVisitedHistory: (c, url, isReload) {
                  if (url != null) _onUrl(url.toString());
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
