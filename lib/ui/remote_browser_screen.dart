import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../remote/agent_server_client.dart';

/// 서버 브라우저 화면을 실시간으로 보고 직접 조작하는 화면.
/// 로그인, 캡차, 인증번호, 결제 비밀번호처럼 사용자가 해야 하는 일에 쓴다.
class RemoteBrowserScreen extends StatefulWidget {
  const RemoteBrowserScreen({
    super.key,
    required this.client,
    required this.title,
    this.message,
    this.paymentMode = false,
    this.closeSignal,
  });

  final AgentServerClient client;
  final String title;
  final String? message;

  /// 결제 모드: [완료]를 누르면 결제를 마쳤는지 묻고 true/false 로 닫힌다.
  final bool paymentMode;

  /// true 가 되면 스스로 닫힌다 (서버가 결제 완료를 감지한 경우).
  final ValueListenable<bool>? closeSignal;

  @override
  State<RemoteBrowserScreen> createState() => _RemoteBrowserScreenState();
}

class _RemoteBrowserScreenState extends State<RemoteBrowserScreen> {
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Uint8List? _frame;
  double _cssWidth = 412;
  double _cssHeight = 839;
  String _url = '';
  String? _error;
  final _text = TextEditingController();
  bool _secret = false; // 비밀번호 입력 시 글자 가리기

  @override
  void initState() {
    super.initState();
    _connect();
    widget.closeSignal?.addListener(_onCloseSignal);
  }

  void _onCloseSignal() {
    if (widget.closeSignal!.value && mounted) Navigator.of(context).pop(true);
  }

  Future<void> _done() async {
    if (!widget.paymentMode) {
      Navigator.of(context).pop();
      return;
    }
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
    if (completed != null && mounted) Navigator.of(context).pop(completed);
  }

  void _connect() {
    setState(() => _error = null);
    final ch = WebSocketChannel.connect(widget.client.liveUri);
    _channel = ch;
    _sub = ch.stream.listen(
      (raw) {
        final msg = jsonDecode(raw as String) as Map<String, dynamic>;
        if (msg['type'] == 'frame') {
          setState(() {
            _frame = base64Decode(msg['data'] as String);
            _cssWidth = (msg['width'] as num?)?.toDouble() ?? _cssWidth;
            _cssHeight = (msg['height'] as num?)?.toDouble() ?? _cssHeight;
            _url = msg['url'] as String? ?? _url;
          });
        } else if (msg['type'] == 'error') {
          _snack('${msg['message']}');
        }
      },
      onError: (Object e) => setState(() => _error = '연결 오류: $e'),
      onDone: () {
        if (mounted) setState(() => _error ??= '서버와 연결이 끊겼습니다.');
      },
    );
  }

  void _send(Map<String, dynamic> event) => _channel?.sink.add(jsonEncode(event));

  void _snack(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  void dispose() {
    widget.closeSignal?.removeListener(_onCloseSignal);
    _sub?.cancel();
    _channel?.sink.close();
    _text.dispose();
    super.dispose();
  }

  Future<void> _openUrl() async {
    final c = TextEditingController(text: _url);
    final url = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('주소 열기'),
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
    if (url == null || url.isEmpty) return;
    _send({'type': 'navigate', 'url': url.startsWith('http') ? url : 'https://$url'});
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title),
            if (_url.isNotEmpty)
              Text(
                Uri.tryParse(_url)?.host ?? _url,
                style: Theme.of(context).textTheme.bodySmall,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: '뒤로',
            icon: const Icon(Icons.arrow_back_ios_new),
            onPressed: () => _send({'type': 'back'}),
          ),
          IconButton(tooltip: '주소 열기', icon: const Icon(Icons.public), onPressed: _openUrl),
          FilledButton.icon(
            onPressed: _done,
            icon: const Icon(Icons.check),
            label: const Text('완료'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Material(
            color: scheme.secondaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  Icon(Icons.cloud, color: scheme.onSecondaryContainer, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${widget.message ?? '서버 브라우저를 직접 조작합니다.'}\n'
                      '화면을 탭하고, 글자는 아래 입력창으로 보내세요. 끝나면 [완료].',
                      style: TextStyle(color: scheme.onSecondaryContainer, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: _error != null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!),
                        const SizedBox(height: 8),
                        FilledButton(onPressed: _connect, child: const Text('다시 연결')),
                      ],
                    ),
                  )
                : _frame == null
                ? const Center(child: CircularProgressIndicator())
                : Center(
                    child: AspectRatio(
                      aspectRatio: _cssWidth / _cssHeight,
                      child: LayoutBuilder(
                        builder: (context, box) {
                          final scale = _cssWidth / box.maxWidth; // 화면 좌표 → 서버 CSS 픽셀
                          return GestureDetector(
                            onTapUp: (d) => _send({
                              'type': 'tap',
                              'x': d.localPosition.dx * scale,
                              'y': d.localPosition.dy * scale,
                            }),
                            onVerticalDragUpdate: (d) =>
                                _send({'type': 'scroll', 'dy': -d.delta.dy * scale * 2}),
                            child: Image.memory(_frame!, gaplessPlayback: true, fit: BoxFit.fill),
                          );
                        },
                      ),
                    ),
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              child: Row(
                children: [
                  IconButton(
                    tooltip: '지우기',
                    icon: const Icon(Icons.backspace_outlined),
                    onPressed: () => _send({'type': 'key', 'key': 'Backspace'}),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _text,
                      obscureText: _secret,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: InputDecoration(
                        hintText: '입력할 글자 (탭한 칸에 입력됨)',
                        isDense: true,
                        suffixIcon: IconButton(
                          tooltip: '글자 가리기',
                          icon: Icon(_secret ? Icons.lock : Icons.lock_open),
                          onPressed: () => setState(() => _secret = !_secret),
                        ),
                      ),
                      onSubmitted: (_) => _typeText(),
                    ),
                  ),
                  IconButton(tooltip: '입력', icon: const Icon(Icons.keyboard), onPressed: _typeText),
                  IconButton(
                    tooltip: 'Enter',
                    icon: const Icon(Icons.keyboard_return),
                    onPressed: () => _send({'type': 'key', 'key': 'Enter'}),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _typeText() {
    if (_text.text.isEmpty) return;
    _send({'type': 'type', 'text': _text.text});
    _text.clear();
  }
}
