import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'agent/agent_controller.dart';
import 'browser/session_store.dart';
import 'core/settings_store.dart';
import 'google/google_auth.dart';
import 'google/writing_style.dart';
import 'openai/chatgpt_auth.dart';
import 'ui/app_theme.dart';
import 'ui/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final chatgpt = ChatGptAuth();
  final settings = SettingsStore(chatgpt: chatgpt);
  final sessions = SiteSessionStore();
  final google = GoogleAuthService();
  final writingStyle = WritingStyleStore();
  await Future.wait([settings.load(), sessions.load(), chatgpt.load(), writingStyle.load()]);
  // Google 로그인 복원은 기다리지 않는다 (설정이 없으면 오류만 표시).
  unawaited(google.init());
  final navigatorKey = GlobalKey<NavigatorState>();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: sessions),
        ChangeNotifierProvider.value(value: google),
        ChangeNotifierProvider.value(value: chatgpt),
        ChangeNotifierProvider.value(value: writingStyle),
        ChangeNotifierProvider(
          create: (_) => AgentController(
            settings: settings,
            sessions: sessions,
            google: google,
            writingStyle: writingStyle,
            navigatorKey: navigatorKey,
          )..attachToServer(),
        ),
      ],
      child: AiAgentApp(navigatorKey: navigatorKey),
    ),
  );
}

class AiAgentApp extends StatelessWidget {
  const AiAgentApp({super.key, required this.navigatorKey});

  final GlobalKey<NavigatorState> navigatorKey;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Agent',
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(Brightness.light),
      darkTheme: buildAppTheme(Brightness.dark),
      home: const HomeScreen(),
    );
  }
}
