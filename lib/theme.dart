// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:material_ui/material_ui.dart';

const String appName = '拼豆工坊';
const String appNameEn = 'Bead Studio';
const String appId = 'work.dawncall.bean';
const String appWebsite = 'https://bean.dawncall.work';
const String appRepository = 'colisys/bean-studio';
const String appVersionBase = '1.0.2';
const String appVersion = String.fromEnvironment(
  'APP_VERSION',
  defaultValue: appVersionBase,
);
const String appCommit = String.fromEnvironment('GIT_COMMIT');
const String appLicense = 'GPL-3.0-or-later';
const String appReleasesUrl =
    'https://github.com/colisys/bean-studio/releases';

/// Version shown in About / footer, including the short git commit supplied by CI.
String get appVersionLabel {
  if (appCommit.isEmpty || appVersion.contains(appCommit)) {
    return appVersion;
  }
  return '$appVersion+g$appCommit';
}

const Color beadCoral = Color(0xFFE85D75);
const Color beadTeal = Color(0xFF2BA39A);
const Color beadAmber = Color(0xFFF2B23E);
const Color beadInk = Color(0xFF2A2420);
const Color boardCream = Color(0xFFF5EFE3);

ThemeData buildBeadTheme(Brightness brightness) {
  final isLight = brightness == Brightness.light;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: beadCoral,
        brightness: brightness,
      ).copyWith(
        surface: isLight ? const Color(0xFFFBF7EF) : const Color(0xFF151310),
        surfaceContainerLowest: isLight
            ? const Color(0xFFFFFFFF)
            : const Color(0xFF0E0D0B),
        surfaceContainerLow: isLight
            ? const Color(0xFFF5EFE5)
            : const Color(0xFF1D1A17),
        surfaceContainer: isLight
            ? const Color(0xFFEFE8DC)
            : const Color(0xFF24211D),
        surfaceContainerHigh: isLight
            ? const Color(0xFFE9E1D4)
            : const Color(0xFF2C2823),
        surfaceContainerHighest: isLight
            ? const Color(0xFFE2D9CA)
            : const Color(0xFF35302A),
        outlineVariant: isLight
            ? const Color(0xFFE3D9CA)
            : const Color(0xFF3B362F),
      );

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    splashFactory: InkSparkle.splashFactory,
  );

  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: scheme.onSurface,
        fontSize: 18,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.2,
      ),
    ),
    cardTheme: CardThemeData(
      color: scheme.surfaceContainerLow,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        shape: const StadiumBorder(),
        side: BorderSide(color: scheme.outlineVariant),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHigh.withValues(
        alpha: isLight ? 0.55 : 0.35,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: const StadiumBorder(),
      side: BorderSide.none,
      backgroundColor: scheme.surfaceContainerHigh.withValues(alpha: 0.55),
      selectedColor: scheme.primaryContainer,
      labelStyle: TextStyle(
        color: scheme.onSurfaceVariant,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: isLight ? beadInk : const Color(0xFFF1E9DE),
      contentTextStyle: TextStyle(
        color: isLight ? const Color(0xFFFFF9F2) : beadInk,
        fontSize: 13,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    tooltipTheme: const TooltipThemeData(
      waitDuration: Duration(milliseconds: 700),
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant,
      thickness: 1,
      space: 1,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: scheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      showDragHandle: true,
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(scheme.surfaceContainerLow),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
    ),
  );
}
