import 'package:flutter/material.dart';

/// 디자인 토큰 — 원티드 Montage 디자인 시스템(npm @montage-ui/theme 4.1.5, montage.wanted.co.kr)을 흑백으로.
///
/// - 글자색: foreground.neutral primary #171719 · secondary #2E2F33 88% · tertiary #37383C 61% · quaternary 28%
/// - 선: line.neutral #70737C 8%(tertiary) · 22%(primary). 면: surface.neutral.secondary #70737C 8%, background.secondary #F7F7F8
/// - 브랜드 파랑 대신 primary 글자색(#171719)을 강조로 쓴다.
/// - 글자 크기·줄 높이·자간·굵기는 [MontageType] (typography 토큰 그대로).
/// 경고·에러만 activity-timeblock ToastProvider 배색을 남겼다.
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
    tint: Color(0x1470737C), // surface.neutral.secondary
    ink: Color(0xFF171719), // foreground.neutral.primary
    muted: Color(0x9C37383C), // foreground.neutral.tertiary
    line: Color(0x1470737C), // line.neutral.tertiary
    lineStrong: Color(0x3870737C), // line.neutral.primary
    accent: Color(0xFF171719),
    accentInk: Color(0xFFFFFFFF),
    accentSoft: Color(0xFFF7F7F8), // background.neutral.secondary
    warningBg: Color(0xFFFFFBE6),
    warningInk: Color(0xFF744600),
    warningLine: Color(0xFFFAAD14),
    errorBg: Color(0xFFFCE7E7),
    errorInk: Color(0xFFD32F2F),
  );

  static const dark = AppTokens(
    bg: Color(0xFF000000),
    paper: Color(0xFF000000),
    tint: Color(0x0AFFFFFF),
    ink: Color(0xFFFFFFFF),
    muted: Color(0xA6FFFFFF),
    line: Color(0x1AFFFFFF),
    lineStrong: Color(0x40FFFFFF),
    accent: Color(0xFFFFFFFF),
    accentInk: Color(0xFF000000),
    accentSoft: Color(0xFF1A1A1A), // base-200
    warningBg: Color(0xFF3A3106),
    warningInk: Color(0xFFFFC53D),
    warningLine: Color(0xFFFFC53D),
    errorBg: Color(0xFF3A1A1A),
    errorInk: Color(0xFFFF7875),
  );

  // Montage radius 토큰 중에서
  static const double r = 16;
  static const double rSm = 12;
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

/// 원티드 Montage typography 토큰 (@montage-ui/theme 4.1.5 `theme/typography`).
/// 크기·줄 높이는 rem(16px) 기준, 자간은 em. 굵기는 토큰의 regular/medium/bold 중에서.
abstract final class MontageType {
  static TextStyle _t(double size, double line, double em, FontWeight w) =>
      TextStyle(fontSize: size, height: line / size, letterSpacing: em * size, fontWeight: w);

  static const _r = FontWeight.w400, _m = FontWeight.w500, _s = FontWeight.w600, _b = FontWeight.w700;

  static TextStyle display1([FontWeight w = _b]) => _t(56, 72, -0.0319, w);
  static TextStyle display2([FontWeight w = _b]) => _t(40, 52, -0.0282, w);
  static TextStyle display3([FontWeight w = _b]) => _t(36, 48, -0.027, w);
  static TextStyle title1([FontWeight w = _b]) => _t(32, 44, -0.0253, w);
  static TextStyle title2([FontWeight w = _b]) => _t(28, 38, -0.0236, w);
  static TextStyle title3([FontWeight w = _b]) => _t(24, 32, -0.023, w);
  static TextStyle heading1([FontWeight w = _s]) => _t(22, 30, -0.0194, w);
  static TextStyle heading2([FontWeight w = _s]) => _t(20, 28, -0.012, w);
  static TextStyle headline1([FontWeight w = _s]) => _t(18, 26, -0.002, w);
  static TextStyle headline2([FontWeight w = _s]) => _t(17, 24, 0, w);
  static TextStyle body1([FontWeight w = _r]) => _t(16, 24, 0.0057, w);
  static TextStyle body1Reading([FontWeight w = _r]) => _t(16, 26, 0.0057, w);
  static TextStyle body2([FontWeight w = _r]) => _t(15, 22, 0.0096, w);
  static TextStyle body2Reading([FontWeight w = _r]) => _t(15, 24, 0.0096, w);
  static TextStyle label1([FontWeight w = _r]) => _t(14, 20, 0.0145, w);
  static TextStyle label1Reading([FontWeight w = _r]) => _t(14, 22, 0.0145, w);
  static TextStyle label2([FontWeight w = _r]) => _t(13, 18, 0.0194, w);
  static TextStyle caption1([FontWeight w = _r]) => _t(12, 16, 0.0252, w);
  static TextStyle caption2([FontWeight w = _r]) => _t(11, 14, 0.0311, w);

  static const medium = _m;
  static const bold = _b;
  static const semibold = _s;

  /// Material TextTheme 자리에 Montage 단계를 꽂는다.
  static TextTheme textTheme(Color ink, Color muted) => TextTheme(
    displayLarge: display1(),
    displayMedium: display2(),
    displaySmall: display3(),
    headlineLarge: title1(),
    headlineMedium: title2(),
    headlineSmall: title3(),
    titleLarge: heading1(),
    titleMedium: headline1(),
    titleSmall: headline2(),
    bodyLarge: body1(),
    bodyMedium: body2(),
    bodySmall: label1().copyWith(color: muted),
    labelLarge: label1(_s),
    labelMedium: label2(_m),
    labelSmall: caption1(_m),
  ).apply(bodyColor: ink, displayColor: ink, fontFamily: 'Wanted Sans');
}

ThemeData buildAppTheme(Brightness brightness) {
  final t = brightness == Brightness.dark ? AppTokens.dark : AppTokens.light;
  final pillShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTokens.pill));
  final buttonText = MontageType.body1(MontageType.semibold);
  const buttonPadding = EdgeInsets.symmetric(horizontal: 20, vertical: 12);

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
    fontFamily: 'Wanted Sans',
  );

  final text = MontageType.textTheme(t.ink, t.muted);

  return base.copyWith(
    scaffoldBackgroundColor: t.bg,
    canvasColor: t.bg,
    dividerColor: t.line,
    extensions: [t],
    textTheme: text,
    appBarTheme: AppBarTheme(
      backgroundColor: t.bg,
      foregroundColor: t.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: MontageType.heading2().copyWith(color: t.ink, fontFamily: 'Wanted Sans'),
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
      subtitleTextStyle: MontageType.label1().copyWith(color: t.muted, fontFamily: 'Wanted Sans'),
      titleTextStyle: MontageType.body1(MontageType.semibold).copyWith(color: t.ink, fontFamily: 'Wanted Sans'),
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
