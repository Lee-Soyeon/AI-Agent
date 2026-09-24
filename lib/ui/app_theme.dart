import 'package:flutter/material.dart';

/// 디자인 토큰 — algorima/activity-timeblock 의 기본(clean, 토스 스타일) 테마를 그대로 옮겼다.
///
/// 출처: activity-timeblock `app/globals.css` 의 `:root` 와 다크 모드 블록.
/// 경고·에러 배색은 같은 리포 `app/providers/ToastProvider.module.css` 의
/// warning(#fffbe6/#744600, 테두리 #faad14)·error(#fce7e7/#d32f2f) 값.
/// 새 색을 지어내지 말고, 필요하면 저쪽 토큰에서 가져올 것.
@immutable
class AppTokens extends ThemeExtension<AppTokens> {
  const AppTokens({
    required this.bg,
    required this.paper,
    required this.tint,
    required this.ink,
    required this.muted,
    required this.line,
    required this.lineStrong,
    required this.accent,
    required this.accentInk,
    required this.accentSoft,
    required this.warningBg,
    required this.warningInk,
    required this.warningLine,
    required this.errorBg,
    required this.errorInk,
  });

  final Color bg;
  final Color paper;
  final Color tint; // 카드 안쪽 옅은 면
  final Color ink;
  final Color muted;
  final Color line;
  final Color lineStrong;
  final Color accent;
  final Color accentInk;
  final Color accentSoft; // 선택 상태·보조 버튼 배경
  final Color warningBg;
  final Color warningInk;
  final Color warningLine;
  final Color errorBg;
  final Color errorInk;

  static const light = AppTokens(
    bg: Color(0xFFFFFFFF),
    paper: Color(0xFFFFFFFF),
    tint: Color(0xFFF9FAFB),
    ink: Color(0xFF191F28),
    muted: Color(0xFF8B95A1),
    line: Color(0xFFF2F4F6),
    lineStrong: Color(0xFFE5E8EB),
    accent: Color(0xFF3182F6),
    accentInk: Color(0xFFFFFFFF),
    accentSoft: Color(0xFFE8F3FF),
    warningBg: Color(0xFFFFFBE6),
    warningInk: Color(0xFF744600),
    warningLine: Color(0xFFFAAD14),
    errorBg: Color(0xFFFCE7E7),
    errorInk: Color(0xFFD32F2F),
  );

  static const dark = AppTokens(
    bg: Color(0xFF0F1115),
    paper: Color(0xFF17191F),
    tint: Color(0xFF1B1E24),
    ink: Color(0xFFE8EAED),
    muted: Color(0xFF8B95A1),
    line: Color(0xFF22252C),
    lineStrong: Color(0xFF2B2F37),
    accent: Color(0xFF4D94FF),
    accentInk: Color(0xFFFFFFFF),
    accentSoft: Color(0xFF16283F),
    warningBg: Color(0xFF3A3106),
    warningInk: Color(0xFFFFC53D),
    warningLine: Color(0xFFFFC53D),
    errorBg: Color(0xFF3A1A1A),
    errorInk: Color(0xFFFF7875),
  );

  // globals.css: --r / --r-sm / --pill
  static const double r = 20;
  static const double rSm = 14;
  static const double pill = 12;

  // globals.css: --shadow-lg (떠 있는 것에만)
  static const shadowLg = [
    BoxShadow(color: Color(0x14191F28), blurRadius: 16, offset: Offset(0, 4)),
  ];

  /// 테마에 토큰이 없으면(테스트의 기본 ThemeData 등) 밝기에 맞는 기본 토큰을 쓴다.
  static AppTokens of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<AppTokens>() ??
        (theme.brightness == Brightness.dark ? AppTokens.dark : AppTokens.light);
  }

  @override
  AppTokens copyWith() => this;

  @override
  AppTokens lerp(AppTokens? other, double t) => t < 0.5 || other == null ? this : other;
}

ThemeData buildAppTheme(Brightness brightness) {
  final t = brightness == Brightness.dark ? AppTokens.dark : AppTokens.light;
  final pillShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTokens.pill));
  const buttonText = TextStyle(fontSize: 14, fontWeight: FontWeight.w700);
  const buttonPadding = EdgeInsets.symmetric(horizontal: 18, vertical: 11);

  final scheme = ColorScheme(
    brightness: brightness,
    primary: t.accent,
    onPrimary: t.accentInk,
    primaryContainer: t.accentSoft,
    onPrimaryContainer: t.accent,
    secondary: t.accent,
    onSecondary: t.accentInk,
    secondaryContainer: t.accentSoft,
    onSecondaryContainer: t.accent,
    tertiary: t.muted,
    onTertiary: t.paper,
    error: t.errorInk,
    onError: t.paper,
    errorContainer: t.errorBg,
    onErrorContainer: t.errorInk,
    surface: t.paper,
    onSurface: t.ink,
    onSurfaceVariant: t.muted,
    surfaceContainerLowest: t.paper,
    surfaceContainerLow: t.tint,
    surfaceContainer: t.tint,
    surfaceContainerHigh: t.tint,
    surfaceContainerHighest: t.line,
    outline: t.muted,
    outlineVariant: t.lineStrong,
    shadow: const Color(0xFF191F28),
    surfaceTint: Colors.transparent,
  );

  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    // 폰트는 번들하지 않는다 — iOS 기본(SF + Apple SD Gothic Neo)은
    // activity-timeblock 의 Pretendard 폴백 체인과 같다.
  );

  final text = base.textTheme.apply(bodyColor: t.ink, displayColor: t.ink);

  return base.copyWith(
    scaffoldBackgroundColor: t.bg,
    canvasColor: t.bg,
    dividerColor: t.line,
    extensions: [t],
    textTheme: text.copyWith(
      titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.6),
      titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.3),
      titleSmall: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
      bodySmall: text.bodySmall?.copyWith(color: t.muted),
      labelLarge: text.labelLarge?.copyWith(fontWeight: FontWeight.w700),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: t.bg,
      foregroundColor: t.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: t.ink,
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.6,
      ),
    ),
    // 흰 바탕에 옅은 회색 면으로 구분 — 선·그림자 없음
    cardTheme: CardThemeData(
      color: t.tint,
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTokens.r)),
      clipBehavior: Clip.antiAlias,
    ),
    listTileTheme: ListTileThemeData(
      iconColor: t.muted,
      textColor: t.ink,
      subtitleTextStyle: TextStyle(color: t.muted, fontSize: 13),
      titleTextStyle: TextStyle(color: t.ink, fontSize: 15, fontWeight: FontWeight.w600),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTokens.r)),
    ),
    dividerTheme: DividerThemeData(color: t.line, thickness: 1, space: 1),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: t.accent,
        foregroundColor: t.accentInk,
        disabledBackgroundColor: t.line,
        disabledForegroundColor: t.muted,
        shape: pillShape,
        padding: buttonPadding,
        textStyle: buttonText,
        elevation: 0,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: t.accentSoft,
        foregroundColor: t.accent,
        shape: pillShape,
        padding: buttonPadding,
        textStyle: buttonText,
        elevation: 0,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: t.ink,
        backgroundColor: t.tint,
        side: BorderSide(color: t.lineStrong),
        shape: pillShape,
        padding: buttonPadding,
        textStyle: buttonText,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: t.accent,
        shape: pillShape,
        textStyle: buttonText,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(foregroundColor: t.ink)),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: t.tint,
      hintStyle: TextStyle(color: t.muted),
      labelStyle: TextStyle(color: t.muted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppTokens.rSm),
        borderSide: BorderSide(color: t.lineStrong),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppTokens.rSm),
        borderSide: BorderSide(color: t.lineStrong),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppTokens.rSm),
        borderSide: BorderSide(color: t.accent, width: 1.5),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: t.tint,
      selectedColor: t.accentSoft,
      side: BorderSide(color: t.lineStrong),
      labelStyle: TextStyle(color: t.ink, fontSize: 13, fontWeight: FontWeight.w600),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTokens.pill)),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        backgroundColor: t.tint,
        foregroundColor: t.ink,
        selectedBackgroundColor: t.accentSoft,
        selectedForegroundColor: t.accent,
        side: BorderSide(color: t.lineStrong),
        shape: pillShape,
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    // 떠 있는 것(다이얼로그·시트·메뉴·스낵바)만 --shadow-lg 수준으로
    dialogTheme: DialogThemeData(
      backgroundColor: t.paper,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTokens.r)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: t.paper,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppTokens.r)),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: t.paper,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTokens.rSm)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: t.accentSoft,
      contentTextStyle: TextStyle(color: t.accent, fontSize: 14, fontWeight: FontWeight.w700),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTokens.rSm)),
      elevation: 0,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: t.accent, linearTrackColor: t.line),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? t.accentInk : t.paper,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? t.accent : t.lineStrong,
      ),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? t.accent : t.muted,
      ),
    ),
  );
}
