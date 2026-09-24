import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../openai/chatgpt_auth.dart';

/// 설정 화면의 ChatGPT 구독 계정 카드.
class ChatGptAccountTile extends StatelessWidget {
  const ChatGptAccountTile({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<ChatGptAuth>();
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (auth.isSignedIn)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.verified_user, color: theme.colorScheme.primary),
                title: Text(auth.email ?? 'ChatGPT 계정'),
                subtitle: Text('요금제: ${auth.planType ?? '알 수 없음'}'),
                trailing: TextButton(onPressed: auth.signOut, child: const Text('로그아웃')),
              )
            else
              FilledButton.icon(
                onPressed: () => showDialog<void>(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => const ChatGptLoginDialog(),
                ),
                icon: const Icon(Icons.login),
                label: const Text('ChatGPT 계정으로 로그인'),
              ),
            const SizedBox(height: 8),
            Text(
              'ChatGPT Plus/Pro 구독의 사용량으로 에이전트를 실행합니다 (API 키 불필요). '
              'OpenClaw·Hermes 와 같은 Codex 로그인 방식을 쓰므로 로그인 화면에 "Codex"가 표시되고, '
              'Codex 계열 모델만 쓸 수 있습니다. 공개 문서가 없는 방식이라 OpenAI 정책에 따라 막힐 수 있습니다.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// 기기 코드 로그인: 코드 표시 → Safari 에서 입력 → 자동 완료.
class ChatGptLoginDialog extends StatefulWidget {
  const ChatGptLoginDialog({super.key});

  @override
  State<ChatGptLoginDialog> createState() => _ChatGptLoginDialogState();
}

class _ChatGptLoginDialogState extends State<ChatGptLoginDialog> {
  DeviceCode? _code;
  String? _error;
  bool _cancelled = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final auth = context.read<ChatGptAuth>();
    setState(() {
      _code = null;
      _error = null;
    });
    try {
      final code = await auth.requestDeviceCode();
      if (!mounted) return;
      setState(() => _code = code);
      await auth.completeDeviceLogin(code, isCancelled: () => _cancelled || !mounted);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted && !_cancelled) setState(() => _error = '$e');
    }
  }

  Future<void> _copyAndOpen() async {
    final code = _code;
    if (code == null) return;
    await Clipboard.setData(ClipboardData(text: code.userCode));
    await launchUrl(Uri.parse(ChatGptAuth.verificationUrl), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final code = _code;
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('ChatGPT 로그인'),
      content: _error != null
          ? Text(_error!, style: TextStyle(color: theme.colorScheme.error))
          : code == null
          ? const SizedBox(height: 80, child: Center(child: CircularProgressIndicator()))
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '1. 아래 코드를 복사하고 로그인 페이지를 엽니다.\n'
                  '2. ChatGPT 계정으로 로그인한 뒤 코드를 붙여넣습니다.\n'
                  '3. 승인하면 이 창이 자동으로 닫힙니다.',
                ),
                const SizedBox(height: 16),
                SelectableText(
                  code.userCode,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 4,
                  ),
                ),
                const SizedBox(height: 12),
                const LinearProgressIndicator(),
                const SizedBox(height: 8),
                Text(
                  '이 앱에서 직접 시작한 로그인일 때만 진행하세요. '
                  '다른 사람이나 웹사이트가 알려준 코드라면 입력하지 마세요.',
                  style: theme.textTheme.bodySmall,
                ),
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
        if (_error != null) FilledButton(onPressed: _start, child: const Text('다시 시도')),
        if (code != null && _error == null)
          FilledButton.icon(
            onPressed: _copyAndOpen,
            icon: const Icon(Icons.open_in_new),
            label: const Text('코드 복사 후 열기'),
          ),
      ],
    );
  }
}
