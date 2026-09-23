import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'agent/agent_controller.dart';
import 'browser/session_store.dart';
import 'core/settings_store.dart';
import 'google/google_auth.dart';
import 'openai/chatgpt_auth.dart';
import 'ui/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final chatgpt = ChatGptAuth();
  final settings = SettingsStore(chatgpt: chatgpt);
  final sessions = SiteSessionStore();
  final google = GoogleAuthService();
  await Future.wait([settings.load(), sessions.load(), chatgpt.load()]);
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
        ChangeNotifierProvider(
          create: (_) => AgentController(
            settings: settings,
            sessions: sessions,
            google: google,
            navigatorKey: navigatorKey,
          ),
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
    const seed = Color(0xFF5B5BD6);
    return MaterialApp(
      title: 'AI Agent',
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: seed, useMaterial3: true),
      darkTheme: ThemeData(colorSchemeSeed: seed, brightness: Brightness.dark, useMaterial3: true),
      home: const HomeScreen(),
    );
  }
}
