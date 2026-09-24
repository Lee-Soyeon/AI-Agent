import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../agent/agent_controller.dart';
import 'accounts_screen.dart';
import 'chat_list_screen.dart';
import 'guide_screen.dart';
import 'settings_screen.dart';

enum AppTab {
  home('홈', Icons.home_outlined, Icons.home_rounded),
  chat('채팅', Icons.chat_bubble_outline_rounded, Icons.chat_bubble_rounded),
  accounts('로그인', Icons.account_circle_outlined, Icons.account_circle_rounded),
  model('모델', Icons.tune_rounded, Icons.tune_rounded);

  const AppTab(this.label, this.icon, this.activeIcon);

  final String label;
  final IconData icon;
  final IconData activeIcon;
}

/// 하단 탭 선택 상태. 다른 화면(사용법 안내, 작업 화면 등)에서 탭을 바꿀 때 쓴다.
class ShellTabs extends ChangeNotifier {
  AppTab _tab = AppTab.home;

  AppTab get tab => _tab;

  void go(AppTab tab) {
    if (tab == _tab) return;
    _tab = tab;
    notifyListeners();
  }
}

/// 앱의 뼈대: 4개 탭 + 화면 위에 살짝 떠 있는 반투명 하단 탭 바.
class MainShell extends StatelessWidget {
  const MainShell({super.key});

  @override
  Widget build(BuildContext context) {
    final tab = context.watch<ShellTabs>().tab;
    return Scaffold(
      // 본문이 탭 바 뒤까지 이어지고, 탭 바 높이만큼 MediaQuery 아래 여백이 생긴다.
      extendBody: true,
      // 키보드가 올라오면 탭 바는 숨기고, 입력창 위치는 각 탭의 Scaffold 가 맞춘다.
      resizeToAvoidBottomInset: false,
      body: IndexedStack(
        index: tab.index,
        children: const [GuideScreen(), ChatListScreen(), AccountsScreen(), SettingsScreen()],
      ),
      bottomNavigationBar: const FloatingTabBar(),
    );
  }
}

class FloatingTabBar extends StatelessWidget {
  const FloatingTabBar({super.key});

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.viewInsetsOf(context).bottom > 0) return const SizedBox.shrink();
    final tabs = context.watch<ShellTabs>();
    final agent = context.watch<AgentController>();
    final needsYou = agent.pendingApproval != null || agent.pendingQuestion != null;
    final scheme = Theme.of(context).colorScheme;
    final wide = MediaQuery.sizeOf(context).width >= 700;
    final radius = BorderRadius.circular(wide ? 999 : 22);

    final bar = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: scheme.surface.withValues(alpha: 0.8),
              borderRadius: radius,
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Row(
              mainAxisSize: wide ? MainAxisSize.min : MainAxisSize.max,
              children: [
                for (final t in AppTab.values)
                  _wrap(
                    wide,
                    _TabButton(
                      tab: t,
                      active: tabs.tab == t,
                      wide: wide,
                      dot: t == AppTab.chat && needsYou,
                      onTap: () => tabs.go(t),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: wide ? Center(heightFactor: 1, child: bar) : bar,
      ),
    );
  }

  static Widget _wrap(bool wide, Widget child) => wide ? child : Expanded(child: child);
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.tab,
    required this.active,
    required this.wide,
    required this.dot,
    required this.onTap,
  });

  final AppTab tab;
  final bool active;
  final bool wide;
  final bool dot;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = active ? scheme.primary : scheme.onSurfaceVariant;
    final radius = BorderRadius.circular(wide ? 999 : 18);

    Widget icon = Icon(active ? tab.activeIcon : tab.icon, size: wide ? 18 : 22, color: color);
    if (dot) {
      icon = Badge(smallSize: 8, backgroundColor: scheme.error, child: icon);
    }
    final label = Text(
      tab.label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: wide ? 12 : 10.5,
        fontWeight: FontWeight.w600,
        color: color,
        height: 1,
      ),
    );

    return Semantics(
      selected: active,
      button: true,
      label: tab.label,
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: active ? scheme.primaryContainer.withValues(alpha: 0.6) : Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Padding(
            padding: wide
                ? const EdgeInsets.symmetric(horizontal: 16, vertical: 9)
                : const EdgeInsets.fromLTRB(2, 7, 2, 6),
            child: wide
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [icon, const SizedBox(width: 6), label],
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [icon, const SizedBox(height: 3), label],
                  ),
          ),
        ),
      ),
    );
  }
}

/// 탭 화면 목록의 아래 여백: 떠 있는 탭 바에 마지막 항목이 가리지 않도록 한다.
EdgeInsets tabListPadding(BuildContext context) =>
    EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.paddingOf(context).bottom);
