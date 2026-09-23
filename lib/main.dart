import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'agent/agent_controller.dart';
import 'browser/session_store.dart';
import 'core/settings_store.dart';
import 'ui/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = SettingsStore();
  final sessions = SiteSessionStore();
  await Future.wait([settings.load(), sessions.load()]);
  final navigatorKey = GlobalKey<NavigatorState>();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: sessions),
        ChangeNotifierProvider(
          create: (_) =>
              AgentController(settings: settings, sessions: sessions, navigatorKey: navigatorKey),
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
