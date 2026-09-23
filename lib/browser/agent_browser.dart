import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'dom_scripts.dart';
import 'web_settings.dart';

class PageElement {
  PageElement(this.json);

  final Map<String, dynamic> json;

  int get id => json['id'] as int;

  String describe() {
    final b = StringBuffer('[$id] ${json['tag']}');
    if (json['type'] != null) b.write('(${json['type']})');
    if (json['role'] != null) b.write(' role=${json['role']}');
    b.write(' "${json['label'] ?? ''}"');
    final value = json['value'] as String? ?? '';
    if (value.isNotEmpty) b.write(' value="$value"');
    if (json['checked'] != null) b.write(json['checked'] == true ? ' [체크됨]' : ' [체크안됨]');
    if (json['options'] != null) b.write(' options=${jsonEncode(json['options'])}');
    if (json['href'] != null) b.write(' href=${json['href']}');
    if (json['disabled'] == true) b.write(' [비활성]');
    if (json['offscreen'] == true) b.write(' (화면 밖)');
    return b.toString();
  }
}

class PageSnapshot {
  PageSnapshot(this.json);

  final Map<String, dynamic> json;

  String get url => json['url'] as String? ?? '';
  String get title => json['title'] as String? ?? '';
  String get text => json['text'] as String? ?? '';
  List<PageElement> get elements => [
    for (final e in (json['elements'] as List? ?? const []))
      PageElement((e as Map).cast<String, dynamic>()),
  ];

  /// LLM 에게 보여줄 텍스트 형태.
  String toPrompt() {
    final b = StringBuffer()
      ..writeln('URL: $url')
      ..writeln('제목: $title')
      ..writeln('스크롤: ${json['scrollY']}/${json['scrollHeight']} (화면 높이 ${json['viewportHeight']})')
      ..writeln()
      ..writeln('## 화면 텍스트')
      ..writeln(text)
      ..writeln()
      ..writeln('## 조작 가능한 요소 (click/type_text 에 id 사용)');
    for (final e in elements) {
      b.writeln(e.describe());
    }
    return b.toString();
  }
}

class BrowserException implements Exception {
  BrowserException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// 에이전트가 사용하는 브라우저 조작 인터페이스 (테스트에서 가짜로 대체 가능).
abstract class BrowserDriver {
  Future<void> navigate(String url);
  Future<String?> currentUrl();
  Future<PageSnapshot> snapshot();
  Future<Map<String, dynamic>> describe(int id);
  Future<Map<String, dynamic>> click(int id);
  Future<Map<String, dynamic>> typeText(int id, String text, {bool submit = false});
  Future<Map<String, dynamic>> scroll(String direction);
  Future<void> goBack();
  Future<Uint8List?> screenshot();
}

/// 화면에 보이지 않는 헤드리스 웹뷰. 에이전트가 이 브라우저를 조작한다.
class AgentBrowser implements BrowserDriver {
  HeadlessInAppWebView? _headless;
  InAppWebViewController? _controller;
  Completer<void>? _loadStop;

  bool get isRunning => _headless?.isRunning() ?? false;

  Future<InAppWebViewController> _ensure() async {
    if (_controller != null && isRunning) return _controller!;
    final created = Completer<void>();
    _headless = HeadlessInAppWebView(
      // 모바일 레이아웃을 받도록 휴대폰 크기로 만든다.
      initialSize: const Size(412, 900),
      initialSettings: buildWebSettings(),
      initialUrlRequest: URLRequest(url: WebUri('about:blank')),
      onWebViewCreated: (c) {
        _controller = c;
        if (!created.isCompleted) created.complete();
      },
      onLoadStop: (c, url) {
        if (url?.toString() == 'about:blank') return;
        final l = _loadStop;
        if (l != null && !l.isCompleted) l.complete();
      },
      onReceivedError: (c, req, err) {
        if (req.isForMainFrame ?? true) {
          final l = _loadStop;
          if (l != null && !l.isCompleted) l.complete();
        }
      },
      onConsoleMessage: (c, m) {
        if (kDebugMode) debugPrint('[agent-web] ${m.message}');
      },
    );
    await _headless!.run();
    await created.future.timeout(const Duration(seconds: 15));
    return _controller!;
  }

  @override
  Future<void> navigate(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.scheme == 'https' || uri.scheme == 'http')) {
      throw BrowserException('http(s) URL 만 열 수 있습니다: $url');
    }
    final c = await _ensure();
    _loadStop = Completer<void>();
    await c.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
    await _settle(waitForLoad: true);
  }

  @override
  Future<String?> currentUrl() async {
    if (_controller == null) return null;
    return (await _controller!.getUrl())?.toString();
  }

  @override
  Future<PageSnapshot> snapshot() async {
    final raw = await _eval(DomScripts.snapshot());
    if (raw == null) throw BrowserException('페이지를 읽을 수 없습니다 (아직 로드되지 않았을 수 있음).');
    return PageSnapshot(raw);
  }

  @override
  Future<Map<String, dynamic>> describe(int id) async =>
      await _eval(DomScripts.describe(id)) ?? const {'ok': false};

  @override
  Future<Map<String, dynamic>> click(int id) => _act(DomScripts.click(id));

  @override
  Future<Map<String, dynamic>> typeText(int id, String text, {bool submit = false}) =>
      _act(DomScripts.typeText(id, text, submit: submit));

  @override
  Future<Map<String, dynamic>> scroll(String direction) =>
      _act(DomScripts.scroll(direction), settle: const Duration(milliseconds: 600));

  @override
  Future<void> goBack() async {
    final c = await _ensure();
    if (await c.canGoBack()) {
      _loadStop = Completer<void>();
      await c.goBack();
      await _settle(waitForLoad: true);
    }
  }

  @override
  Future<Uint8List?> screenshot() async {
    try {
      return await _controller?.takeScreenshot(
        screenshotConfiguration: ScreenshotConfiguration(
          compressFormat: CompressFormat.JPEG,
          quality: 60,
        ),
      );
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> _act(String js, {Duration? settle}) async {
    _loadStop = Completer<void>();
    final r = await _eval(js) ?? {'ok': false, 'error': '스크립트 실행 실패'};
    await _settle(waitForLoad: false, extra: settle);
    return r;
  }

  Future<Map<String, dynamic>?> _eval(String js) async {
    final c = await _ensure();
    final res = await c.evaluateJavascript(source: js);
    if (res == null) return null;
    final decoded = res is String ? jsonDecode(res) : res;
    return decoded is Map ? decoded.cast<String, dynamic>() : null;
  }

  /// 동작 후 페이지가 안정될 때까지 기다린다. 클릭으로 페이지 이동이 일어날 수도, 안 일어날 수도 있다.
  Future<void> _settle({required bool waitForLoad, Duration? extra}) async {
    final l = _loadStop;
    if (l != null) {
      try {
        await l.future.timeout(
          waitForLoad ? const Duration(seconds: 20) : const Duration(milliseconds: 1500),
        );
      } on TimeoutException {
        // 페이지 이동이 없는 SPA 동작이면 정상.
      }
    }
    final c = _controller;
    if (c != null) {
      final until = DateTime.now().add(const Duration(seconds: 10));
      while (DateTime.now().isBefore(until)) {
        final s = await c.evaluateJavascript(source: DomScripts.readyState);
        if (s == 'complete') break;
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
    }
    // 동적으로 그려지는 콘텐츠를 위해 조금 더 기다린다.
    await Future<void>.delayed(extra ?? const Duration(milliseconds: 900));
  }

  Future<void> dispose() async {
    await _headless?.dispose();
    _headless = null;
    _controller = null;
  }
}
