import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../google/google_auth.dart';
import '../google/google_button.dart';
import 'app_theme.dart';
import 'toss_form.dart';

/// 앱 첫 화면: Google 로 계속하기. 처음이면 가입, 이미 썼다면 로그인이다.
class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final google = context.watch<GoogleAuthService>();
    final t = AppTokens.of(context);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(flex: 3),
              Text('할 일을 말하면\nAI가 끝내 드려요', style: MontageType.title1().copyWith(color: t.ink)),
              const SizedBox(height: 12),
              Text('서류 만들기, 엑셀 정리, 사진 속 글자 옮기기까지', style: MontageType.body1Reading().copyWith(color: t.muted)),
              const Spacer(flex: 4),
              if (google.busy)
                const Center(child: CircularProgressIndicator())
              else if (google.canAuthenticate)
                TossBigButton(label: 'Google로 계속하기', icon: Icons.login, onPressed: google.signIn)
              else
                Center(child: googleWebButton()),
              if (google.error != null) ...[
                const SizedBox(height: 12),
                Text(google.error!, textAlign: TextAlign.center, style: MontageType.label2().copyWith(color: t.errorInk)),
              ],
              const SizedBox(height: 16),
              Text(
                '처음이면 가입, 이미 썼다면 로그인돼요.\n이름과 이메일만 받아요.',
                textAlign: TextAlign.center,
                style: MontageType.label2().copyWith(color: t.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
