import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../agent/agent_controller.dart';
import '../agent/agent_models.dart';
import 'app_theme.dart';

/// 에이전트 브라우저 뷰포트 비율 (agent_browser.dart 의 initialSize 412×900).
const _viewportRatio = 412 / 900;
const _pipWidth = 104.0;
const _edge = 12.0;
const _heroTag = 'agent-browser-screen';

/// 가장 최근에 에이전트가 한 동작 — 미니 화면·전체 화면의 캡션.
String? latestAction(List<AgentLogEntry> logs) {
  for (var i = logs.length - 1; i >= 0; i--) {
    if (logs[i].kind == LogKind.action) return logs[i].text;
  }
  return null;
}

/// 로그 위에 떠 있는 백그라운드 브라우저 미니 화면 (PiP).
///
/// - 끌어서 옮기면 가까운 모서리로 붙는다.
/// - 탭하면 전체 화면으로 커지고, − 를 누르면 가장자리의 작은 탭으로 접힌다.
/// - 에이전트가 움직이는 동안은 LIVE 점이 깜박인다.
/// - [dimmed] 가 참이면(사용자가 로그를 스크롤하는 중) 반투명해져 아래 글자가 보인다.
class BrowserPip extends StatefulWidget {
  const BrowserPip({
    super.key,
    required this.screenshot,
    required this.live,
    required this.onOpen,
    this.caption,
    this.dimmed = false,
  });

  final Uint8List screenshot;
  final bool live;
  final String? caption;
  final VoidCallback onOpen;
  final bool dimmed;

  @override
  State<BrowserPip> createState() => _BrowserPipState();
}

class _BrowserPipState extends State<BrowserPip> {
  bool _right = true;
  bool _top = true;
  bool _minimized = false;
  Offset? _drag; // 끄는 중일 때의 좌상단 위치

  static const _pipHeight = _pipWidth / _viewportRatio;

  Offset _anchor(Size box, Size self) => Offset(
    _right ? box.width - self.width - _edge : _edge,
    _top ? _edge : box.height - self.height - _edge,
  );

  void _snap(Size box, Size self) {
    final p = _drag!;
    setState(() {
      _right = p.dx + self.width / 2 > box.width / 2;
      _top = p.dy + self.height / 2 < box.height / 2;
      _drag = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final box = c.biggest;
        // 로그 영역이 좁으면(키보드가 올라온 경우 등) 미니 화면을 줄인다.
        final scale = ((box.height - _edge * 2) / _pipHeight).clamp(0.5, 1.0);
        final self = _minimized ? const Size(44, 44) : Size(_pipWidth * scale, _pipHeight * scale);
        final pos = _drag ?? _anchor(box, self);

        final child = _minimized ? _collapsedTab(context) : _window(context, self);

        return Stack(
          children: [
            AnimatedPositioned(
              duration: _drag == null ? const Duration(milliseconds: 280) : Duration.zero,
              curve: Curves.easeOutCubic,
              left: pos.dx,
              top: pos.dy,
              width: self.width,
              height: self.height,
              child: GestureDetector(
                onPanStart: (_) => setState(() => _drag = pos),
                onPanUpdate: (d) => setState(() {
                  final n = _drag! + d.delta;
                  _drag = Offset(
                    n.dx.clamp(0, box.width - self.width),
                    n.dy.clamp(0, box.height - self.height),
                  );
                }),
                onPanEnd: (_) => _snap(box, self),
                child: AnimatedOpacity(
                  opacity: widget.dimmed && _drag == null ? 0.3 : 1,
                  duration: const Duration(milliseconds: 180),
                  child: child,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _window(BuildContext context, Size self) {
    final t = AppTokens.of(context);
    return Semantics(
      button: true,
      label: '백그라운드 브라우저 화면, 탭해서 크게 보기',
      child: GestureDetector(
        onTap: widget.onOpen,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: t.paper,
            borderRadius: BorderRadius.circular(AppTokens.rSm),
            border: Border.all(color: t.paper, width: 2),
            boxShadow: AppTokens.shadowLg,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppTokens.rSm - 2),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Hero(
                  tag: _heroTag,
                  child: _ScreenImage(bytes: widget.screenshot),
                ),
                // 아래쪽 캡션이 읽히도록 옅은 그라데이션
                if (widget.caption != null)
                  const Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: 56,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x00191F28), Color(0x99191F28)],
                        ),
                      ),
                    ),
                  ),
                if (widget.caption != null)
                  Positioned(
                    left: 7,
                    right: 7,
                    bottom: 6,
                    child: Text(
                      widget.caption!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        height: 1.3,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                Positioned(top: 6, left: 6, child: LiveBadge(live: widget.live, compact: true)),
                Positioned(
                  top: 2,
                  right: 2,
                  child: _RoundIconButton(
                    icon: Icons.remove,
                    tooltip: '미니 화면 접기',
                    onTap: () => setState(() => _minimized = true),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _collapsedTab(BuildContext context) {
    final t = AppTokens.of(context);
    return Tooltip(
      message: '브라우저 화면 펼치기',
      child: Material(
        color: t.paper,
        shape: const CircleBorder(),
        elevation: 0,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => setState(() => _minimized = false),
          child: DecoratedBox(
            decoration: const BoxDecoration(shape: BoxShape.circle, boxShadow: AppTokens.shadowLg),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(Icons.smartphone, color: t.accent, size: 22),
                if (widget.live) const Positioned(top: 9, right: 10, child: _PulseDot(size: 7)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 전체 화면 보기 — 스크린샷이 계속 갱신되고, 핀치로 확대할 수 있다.
class BrowserViewerPage extends StatelessWidget {
  const BrowserViewerPage({super.key});

  static Route<void> route() => PageRouteBuilder<void>(
    opaque: false,
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 300),
    reverseTransitionDuration: const Duration(milliseconds: 250),
    pageBuilder: (_, _, _) => const BrowserViewerPage(),
    transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
  );

  @override
  Widget build(BuildContext context) {
    final agent = context.watch<AgentController>();
    final shot = agent.lastScreenshot;
    final caption = latestAction(agent.logs);
    final live = agent.status == AgentStatus.running;

    return Scaffold(
      backgroundColor: const Color(0xF20F1115), // 다크 --bg
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
              child: Row(
                children: [
                  LiveBadge(live: live),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      '백그라운드 브라우저',
                      style: TextStyle(
                        color: Color(0xFFE8EAED),
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '닫기',
                    color: const Color(0xFFE8EAED),
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Expanded(
              child: shot == null
                  ? const Center(
                      child: Text('화면이 아직 없습니다', style: TextStyle(color: Color(0xFF8B95A1))),
                    )
                  : InteractiveViewer(
                      maxScale: 4,
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: AspectRatio(
                            aspectRatio: _viewportRatio,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(AppTokens.r),
                              child: Hero(
                                tag: _heroTag,
                                child: _ScreenImage(bytes: shot),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: caption == null
                  ? const SizedBox(height: 16)
                  : Container(
                      key: ValueKey(caption),
                      width: double.infinity,
                      margin: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1B1E24), // 다크 --tint
                        borderRadius: BorderRadius.circular(AppTokens.rSm),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.touch_app, size: 18, color: Color(0xFF4D94FF)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              caption,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Color(0xFFE8EAED), fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 새 스크린샷이 오면 깜박이지 않고 부드럽게 바꿔 끼운다.
class _ScreenImage extends StatelessWidget {
  const _ScreenImage({required this.bytes});

  final Uint8List bytes;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      layoutBuilder: (current, previous) =>
          Stack(fit: StackFit.expand, children: [...previous, ?current]),
      child: Image.memory(
        bytes,
        key: ValueKey(identityHashCode(bytes)),
        fit: BoxFit.cover,
        alignment: Alignment.topCenter,
        gaplessPlayback: true,
      ),
    );
  }
}

/// "LIVE" 표시 — 에이전트가 움직이는 동안만 점이 깜박인다.
class LiveBadge extends StatelessWidget {
  const LiveBadge({super.key, required this.live, this.compact = false});

  final bool live;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 5 : 8, vertical: compact ? 2 : 4),
      decoration: BoxDecoration(
        color: const Color(0x99191F28),
        borderRadius: BorderRadius.circular(AppTokens.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          live
              ? _PulseDot(size: compact ? 5 : 7)
              : Container(
                  width: compact ? 5 : 7,
                  height: compact ? 5 : 7,
                  decoration: const BoxDecoration(color: Color(0xFF8B95A1), shape: BoxShape.circle),
                ),
          SizedBox(width: compact ? 4 : 6),
          Text(
            live ? 'LIVE' : '멈춤',
            style: TextStyle(
              color: Colors.white,
              fontSize: compact ? 8.5 : 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _PulseDot extends StatefulWidget {
  const _PulseDot({required this.size});

  final double size;

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 0.35, end: 1.0).animate(_c),
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(color: AppTokens.of(context).accent, shape: BoxShape.circle),
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({required this.icon, required this.tooltip, required this.onTap});

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        // 보이는 원은 작아도 누르는 영역은 넉넉하게
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Container(
            width: 20,
            height: 20,
            decoration: const BoxDecoration(color: Color(0x99191F28), shape: BoxShape.circle),
            child: Icon(icon, size: 14, color: Colors.white),
          ),
        ),
      ),
    );
  }
}
