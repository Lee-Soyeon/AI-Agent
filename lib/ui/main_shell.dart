import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../agent/agent_controller.dart';
import 'app_theme.dart';
import 'accounts_screen.dart';
import 'chat_list_screen.dart';
import 'guide_screen.dart';
import 'settings_screen.dart';

enum AppTab {
  home('홈', StrokeIcons.home),
  chat('채팅', StrokeIcons.chat),
  accounts('로그인', StrokeIcons.person),
  model('모델', StrokeIcons.sliders);

  const AppTab(this.label, this.icon);

  final String label;
  final Path Function() icon;
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

/// activity-timeblock `app/BottomTabBar.module.css` 를 그대로 옮긴 하단 탭 바.
/// 화면에서 살짝 떠 있는 반투명 바 — paper 80% + blur(14px) saturate(1.4) + --shadow-lg.
/// 좁은 화면(≤380)은 여백·글자를 줄이고, 넓은 화면(≥980)은 가운데 뜬 알약형 가로 바.
class FloatingTabBar extends StatelessWidget {
  const FloatingTabBar({super.key});

  static const _narrow = 380.0;
  static const _desktop = 980.0;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.viewInsetsOf(context).bottom > 0) return const SizedBox.shrink();
    final tabs = context.watch<ShellTabs>();
    final agent = context.watch<AgentController>();
    final needsYou = agent.pendingApproval != null || agent.pendingQuestion != null;
    final t = AppTokens.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final desktop = width >= _desktop;
    final narrow = width <= _narrow;
    final radius = BorderRadius.circular(desktop ? AppTokens.pill : 22);

    final bar = DecoratedBox(
      decoration: BoxDecoration(borderRadius: radius, boxShadow: AppTokens.shadowLg),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.compose(
            outer: _saturate(1.4),
            inner: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          ),
          child: Container(
            padding: desktop
                ? const EdgeInsets.symmetric(horizontal: 6, vertical: 4)
                : const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: t.paper.withValues(alpha: 0.8),
              borderRadius: radius,
              // clean 테마는 --border-w: 0 이라 테두리 없음
            ),
            child: Row(
              mainAxisSize: desktop ? MainAxisSize.min : MainAxisSize.max,
              spacing: desktop ? 2 : 0,
              children: [
                for (final tab in AppTab.values)
                  _wrap(
                    desktop,
                    _TabButton(
                      tab: tab,
                      active: tabs.tab == tab,
                      desktop: desktop,
                      narrow: narrow,
                      dot: tab == AppTab.chat && needsYou,
                      onTap: () => tabs.go(tab),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    final side = narrow ? 8.0 : 10.0;
    return SafeArea(
      top: false,
      minimum: EdgeInsets.fromLTRB(side, 0, side, desktop ? 20 : 10),
      child: desktop ? Center(heightFactor: 1, child: bar) : bar,
    );
  }

  static Widget _wrap(bool desktop, Widget child) => desktop ? child : Expanded(child: child);

  /// CSS `saturate(s)` 와 같은 색 행렬.
  static ColorFilter _saturate(double s) {
    const r = 0.2126, g = 0.7152, b = 0.0722;
    return ColorFilter.matrix([
      r + (1 - r) * s, g - g * s, b - b * s, 0, 0, //
      r - r * s, g + (1 - g) * s, b - b * s, 0, 0, //
      r - r * s, g - g * s, b + (1 - b) * s, 0, 0, //
      0, 0, 0, 1, 0,
    ]);
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.tab,
    required this.active,
    required this.desktop,
    required this.narrow,
    required this.dot,
    required this.onTap,
  });

  final AppTab tab;
  final bool active;
  final bool desktop;
  final bool narrow;
  final bool dot;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final color = active ? t.accent : t.muted;
    final radius = BorderRadius.circular(desktop ? AppTokens.pill : 18);

    Widget icon = StrokeIcon(tab.icon, size: desktop ? 18 : 22, color: color);
    if (dot) {
      // 승인·답변 대기 — 경고 배색은 ToastProvider 의 error 값
      icon = Badge(smallSize: 7, backgroundColor: t.errorInk, child: icon);
    }
    final label = Text(
      tab.label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: desktop ? 12 : (narrow ? 9.5 : 10.5),
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
        color: active ? t.accentSoft : Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          splashColor: Colors.transparent, // -webkit-tap-highlight-color: transparent
          highlightColor: t.accentSoft.withValues(alpha: 0.5),
          child: Padding(
            padding: desktop
                ? const EdgeInsets.symmetric(horizontal: 16, vertical: 9)
                : EdgeInsets.fromLTRB(narrow ? 1 : 2, 7, narrow ? 1 : 2, 6),
            child: desktop
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

/// activity-timeblock 탭 아이콘과 같은 스트로크 라인 아이콘 (24 격자, 획 1.8, 둥근 끝).
/// 장식 없이 획 하나로만 구성한다 — app/CLAUDE.md UI 원칙.
class StrokeIcon extends StatelessWidget {
  const StrokeIcon(this.path, {super.key, this.size = 22, required this.color});

  final Path Function() path;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _StrokePainter(path, color));
}

class _StrokePainter extends CustomPainter {
  _StrokePainter(this.path, this.color);

  final Path Function() path;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 24;
    canvas.scale(k);
    canvas.drawPath(
      path(),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(_StrokePainter old) => old.color != color || old.path != path;
}

abstract final class StrokeIcons {
  /// 집 — 사용법 안내 홈.
  static Path home() => Path()
    ..moveTo(4.5, 10.2)
    ..lineTo(12, 4)
    ..lineTo(19.5, 10.2)
    ..lineTo(19.5, 19)
    ..arcToPoint(const Offset(18, 20.5), radius: const Radius.circular(1.5))
    ..lineTo(14.5, 20.5)
    ..lineTo(14.5, 15)
    ..lineTo(9.5, 15)
    ..lineTo(9.5, 20.5)
    ..lineTo(6, 20.5)
    ..arcToPoint(const Offset(4.5, 19), radius: const Radius.circular(1.5))
    ..close();

  /// 말풍선 — activity-timeblock "AI 채팅" 탭과 같은 path (M4 5.5h16v10.5H9.5L5 20v-4H4z).
  static Path chat() => Path()
    ..moveTo(4, 5.5)
    ..lineTo(20, 5.5)
    ..lineTo(20, 16)
    ..lineTo(9.5, 16)
    ..lineTo(5, 20)
    ..lineTo(5, 16)
    ..lineTo(4, 16)
    ..close();

  /// 사람 — activity-timeblock "마이페이지" 탭과 같은 path.
  static Path person() => Path()
    ..addOval(Rect.fromCircle(center: const Offset(12, 8.2), radius: 3.4))
    ..moveTo(4.8, 20)
    ..cubicTo(5.9, 16.4, 8.8, 14.6, 12, 14.6)
    ..cubicTo(15.2, 14.6, 18.1, 16.4, 19.2, 20);

  /// 슬라이더 — 모델 설정.
  static Path sliders() => Path()
    ..moveTo(4, 7.5)
    ..lineTo(12.5, 7.5)
    ..moveTo(17.5, 7.5)
    ..lineTo(20, 7.5)
    ..addOval(Rect.fromCircle(center: const Offset(15, 7.5), radius: 2.5))
    ..moveTo(4, 16.5)
    ..lineTo(6.5, 16.5)
    ..moveTo(11.5, 16.5)
    ..lineTo(20, 16.5)
    ..addOval(Rect.fromCircle(center: const Offset(9, 16.5), radius: 2.5));
}

/// 탭 화면 목록의 아래 여백: 떠 있는 탭 바에 마지막 항목이 가리지 않도록 한다.
EdgeInsets tabListPadding(BuildContext context) =>
    EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.paddingOf(context).bottom);
