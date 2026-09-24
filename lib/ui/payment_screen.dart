import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../agent/agent_models.dart';
import '../browser/app_scheme.dart';
import '../browser/dom_scripts.dart';
import '../browser/web_settings.dart';

/// 에이전트가 준비한 결제 직전 화면을 **같은 세션 그대로** 사용자에게 보여준다.
///
/// - 에이전트의 헤드리스 웹뷰를 화면에 붙이므로 주문서·선택한 결제수단이 그대로 남아 있다.
/// - 안심결제·ISP 결제창(새 창)을 화면 위에 띄우고, 카드사·은행 앱 호출 주소를 실행한다.
/// - 주문·결제 완료 페이지를 감지하면 자동으로 닫고 에이전트에게 돌아간다.
class PaymentScreen extends StatefulWidget {
  const PaymentScreen({super.key, required this.request, this.headless, this.fallbackUrl});

  final ApprovalRequest request;

  /// 에이전트가 쓰던 브라우저. 없으면 [fallbackUrl] 을 새로 연다.
  final HeadlessInAppWebView? headless;
  final String? fallbackUrl;

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  InAppWebViewController? _controller;
  CreateWindowAction? _popup;
  String? _url;
  bool _done = false;
  bool _closing = false;
  Timer? _watch;

  @override
  void initState() {
    super.initState();
    // 결제 완료 화면이 페이지 이동 없이(SPA) 바뀌는 경우도 있어 주기적으로 확인한다.
    _watch = Timer.periodic(const Duration(seconds: 2), (_) => _checkDone());
  }

  @override
  void dispose() {
    _watch?.cancel();
    super.dispose();
  }

  InAppWebViewSettings get _settings => buildWebSettings()
    ..supportMultipleWindows = true
    ..javaScriptCanOpenWindowsAutomatically = true
    ..useShouldOverrideUrlLoading = true;

  Future<NavigationActionPolicy> _override(
    InAppWebViewController c,
    NavigationAction action,
  ) async {
    final uri = action.request.url;
    if (uri == null || isWebScheme(uri.scheme)) return NavigationActionPolicy.ALLOW;
    // 카드사·은행 앱 호출 (ispmobile://, kb-acp://, intent://…)
    final ok = await launchAppUrl(uri.toString());
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('카드사·은행 앱을 열 수 없습니다. 앱이 설치되어 있는지 확인하거나 다른 결제수단을 선택하세요.')),
      );
    }
    return NavigationActionPolicy.CANCEL;
  }

  Future<void> _checkDone() async {
    final c = _controller;
    if (c == null || _done || _closing) return;
    try {
      final raw = await c.evaluateJavascript(source: DomScripts.paymentDone);
      final r = jsonDecode(raw as String) as Map<String, dynamic>;
      _url = r['url'] as String? ?? _url;
      if (r['done'] == true) {
        setState(() => _done = true);
        await Future<void>.delayed(const Duration(milliseconds: 1500)); // 완료 화면을 잠깐 보여준다
        _close(completed: true);
      }
    } catch (_) {
      // 페이지 이동 중이면 다음 확인 때 다시 본다
    }
  }

  Future<void> _close({required bool completed}) async {
    if (_closing) return;
    _closing = true;
    final url = (await _controller?.getUrl())?.toString() ?? _url;
    if (mounted) {
      Navigator.of(context).pop(PaymentOutcome(approved: true, completed: completed, url: url));
    }
  }

  Future<void> _confirmClose() async {
    final completed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('결제를 마쳤나요?'),
        content: const Text('결제를 마쳤다면 에이전트가 주문 내역을 확인하고 마무리합니다.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('결제 안 함')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('결제 완료')),
        ],
      ),
    );
    if (completed != null) _close(completed: completed);
  }

  Widget _webView() => InAppWebView(
    headlessWebView: widget.headless,
    initialUrlRequest: widget.headless == null && widget.fallbackUrl != null
        ? URLRequest(url: WebUri(widget.fallbackUrl!))
        : null,
    initialSettings: _settings,
    onWebViewCreated: (c) async {
      _controller = c;
      // 헤드리스에서 넘겨받은 경우 initialSettings 가 적용되지 않으므로 다시 설정한다.
      await c.setSettings(settings: _settings);
    },
    shouldOverrideUrlLoading: _override,
    onCreateWindow: (c, action) async {
      setState(() => _popup = action);
      return true;
    },
    onLoadStop: (c, url) {
      _url = url?.toString() ?? _url;
      _checkDone();
    },
  );

  Widget _popupView(CreateWindowAction action) => Positioned.fill(
    child: Material(
      color: Colors.black54,
      child: SafeArea(
        child: Column(
          children: [
            Container(
              color: Theme.of(context).colorScheme.surface,
              child: Row(
                children: [
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Text('결제창', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => _popup = null),
                  ),
                ],
              ),
            ),
            Expanded(
              child: InAppWebView(
                windowId: action.windowId,
                initialSettings: _settings,
                shouldOverrideUrlLoading: _override,
                onCloseWindow: (_) {
                  if (mounted) setState(() => _popup = null);
                  _checkDone();
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final r = widget.request;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (_popup != null) {
          setState(() => _popup = null);
        } else if (await _controller?.canGoBack() ?? false) {
          await _controller!.goBack();
        } else {
          await _confirmClose();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('결제'),
          actions: [
            TextButton(onPressed: _confirmClose, child: const Text('닫기')),
            const SizedBox(width: 8),
          ],
        ),
        body: Column(
          children: [
            Material(
              color: _done ? Colors.green.shade100 : scheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      _done ? Icons.check_circle : Icons.payments,
                      color: scheme.onPrimaryContainer,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _done ? '결제가 완료되었습니다. 돌아갑니다…' : r.title,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          if (!_done) ...[
                            const SizedBox(height: 2),
                            Text(r.summary, maxLines: 3, overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 4),
                            Text(
                              '아래에서 결제하기를 누르고 결제 비밀번호·카드 인증을 마치세요. '
                              '카드사 앱으로 넘어갔다면 인증 후 이 앱으로 돌아오세요. 완료되면 자동으로 닫힙니다.',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(child: Stack(children: [_webView(), if (_popup != null) _popupView(_popup!)])),
          ],
        ),
      ),
    );
  }
}
