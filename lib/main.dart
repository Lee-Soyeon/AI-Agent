import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'agent/agent_controller.dart';
import 'browser/session_store.dart';
import 'core/settings_store.dart';
import 'google/google_auth.dart';
import 'google/writing_style.dart';
import 'openai/chatgpt_auth.dart';
import 'services/service_catalog.dart';
import 'slack/slack_store.dart';
import 'ui/app_theme.dart';
import 'ui/main_shell.dart';
import 'workfilter/share_intent_controller.dart';
import 'workfilter/work_filter_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final chatgpt = ChatGptAuth();
  final settings = SettingsStore(chatgpt: chatgpt);
  final sessions = SiteSessionStore();
  final google = GoogleAuthService();
  final writingStyle = WritingStyleStore();
  final slack = SlackStore();
  final workFilter = WorkFilterStore();
  final catalog = await ServiceCatalog.load();
  await Future.wait([
    settings.load(),
    sessions.load(),
    chatgpt.load(),
    writingStyle.load(),
    slack.load(),
    workFilter.load(),
  ]);
  // Google 로그인 복원은 기다리지 않는다 (설정이 없으면 오류만 표시).
  unawaited(google.init());
  final shareIntent = ShareIntentController(settings: settings, slack: slack, store: workFilter);
  // 공유 시트(에이닷/문자 → 이 앱)로 들어오는 텍스트 수신 시작. iOS 는 Share Extension 설정이
  // 필요하며, 설정 전에는 그냥 아무것도 들어오지 않는다 (docs/work-filter-slack-setup.md 참고).
  unawaited(shareIntent.init());
  final navigatorKey = GlobalKey<NavigatorState>();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: sessions),
        ChangeNotifierProvider.value(value: google),
        ChangeNotifierProvider.value(value: chatgpt),
        ChangeNotifierProvider.value(value: writingStyle),
        ChangeNotifierProvider.value(value: slack),
        ChangeNotifierProvider.value(value: workFilter),
        ChangeNotifierProvider.value(value: shareIntent),
        Provider.value(value: catalog),
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
      home: const MainShell(),
    );
  }
}
