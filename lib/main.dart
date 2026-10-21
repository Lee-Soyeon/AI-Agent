import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'agent/agent_controller.dart';
import 'browser/session_store.dart';
import 'core/settings_store.dart';
import 'google/google_auth.dart';
import 'google/writing_style.dart';
import 'openai/chatgpt_auth.dart';
import 'recipes/recipe_catalog.dart';
import 'services/service_catalog.dart';
import 'ui/app_theme.dart';
import 'ui/main_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final chatgpt = ChatGptAuth();
  final settings = SettingsStore(chatgpt: chatgpt);
  final sessions = SiteSessionStore();
  final google = GoogleAuthService();
  final writingStyle = WritingStyleStore();
  final catalog = await ServiceCatalog.load();
  RecipeCatalog recipes;
  try {
    recipes = await RecipeCatalog.load();
  } catch (_) {
    recipes = RecipeCatalog.empty();
  }
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
        Provider.value(value: catalog),
        Provider<RecipeCatalog?>.value(value: recipes),
        ChangeNotifierProvider(create: (_) => ShellTabs()),
        ChangeNotifierProvider(
          create: (_) => AgentController(
            settings: settings,
            sessions: sessions,
            google: google,
            writingStyle: writingStyle,
            navigatorKey: navigatorKey,
            catalog: catalog,
          )..init(),
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
      // 모바일 웹 먼저 (PRD 7): 넓은 화면에서는 가운데 폰 폭 컬럼으로.
      builder: (context, child) => PhoneFrame(child: child ?? const SizedBox.shrink()),
      home: const MainShell(),
    );
  }
}

/// 폭이 넓으면(데스크톱) 430px 컬럼을 가운데 두고 바깥은 옅은 면으로 채운다.
class PhoneFrame extends StatelessWidget {
  const PhoneFrame({super.key, required this.child});

  final Widget child;

  static const width = 430.0;
  static const threshold = 480.0;

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w <= threshold) return child;
    final t = AppTokens.of(context);
    return ColoredBox(
      color: t.tint,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: width),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: t.bg,
              border: Border.symmetric(vertical: BorderSide(color: t.lineStrong)),
            ),
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(size: Size(width, MediaQuery.sizeOf(context).height)),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
