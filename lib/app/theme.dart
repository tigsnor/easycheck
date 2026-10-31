import 'package:flutter/material.dart';

ThemeData buildEasyCheckTheme() {
  const ink = Color(0xFF1E293B);
  const secondaryInk = Color(0xFF475569);
  const background = Color(0xFFF8FAFC);
  final colors = ColorScheme.fromSeed(
    seedColor: const Color(0xFF0F766E),
    brightness: Brightness.light,
    primary: const Color(0xFF0F766E),
    onPrimary: Colors.white,
    primaryContainer: const Color(0xFFCCFBF1),
    onPrimaryContainer: const Color(0xFF134E4A),
    secondary: secondaryInk,
    onSecondary: Colors.white,
    secondaryContainer: const Color(0xFFE8EEF4),
    onSecondaryContainer: ink,
    // Keep large surfaces neutral; teal is reserved for actions and selection.
    surface: background,
    surfaceDim: const Color(0xFFE2E8F0),
    surfaceBright: Colors.white,
    surfaceContainerLowest: Colors.white,
    surfaceContainer: const Color(0xFFF1F5F9),
    surfaceContainerHigh: const Color(0xFFF1F5F9),
    surfaceTint: Colors.transparent,
    onSurface: ink,
    onSurfaceVariant: secondaryInk,
    surfaceContainerLow: Colors.white,
    surfaceContainerHighest: const Color(0xFFE8EEF4),
    outline: const Color(0xFF64748B),
    outlineVariant: const Color(0xFFCBD5E1),
    error: const Color(0xFFB42318),
    errorContainer: const Color(0xFFFEE4E2),
    onErrorContainer: const Color(0xFF7A271A),
  );
  final base = ThemeData(useMaterial3: true, colorScheme: colors);
  final text = base.textTheme.apply(bodyColor: ink, displayColor: ink);
  return base.copyWith(
    scaffoldBackgroundColor: background,
    textTheme: text.copyWith(
      bodySmall: text.bodySmall?.copyWith(fontSize: 14, color: secondaryInk),
      labelMedium: text.labelMedium?.copyWith(fontSize: 13),
      labelSmall: text.labelSmall?.copyWith(fontSize: 12),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: background,
      foregroundColor: ink,
      elevation: 0,
      centerTitle: false,
      titleTextStyle:
          TextStyle(color: ink, fontSize: 24, fontWeight: FontWeight.w700),
    ),
    cardTheme: const CardThemeData(color: Colors.white),
    dialogTheme: const DialogThemeData(backgroundColor: Colors.white),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.white,
      modalBackgroundColor: Colors.white,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: colors.primaryContainer,
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((states) =>
            !states.contains(WidgetState.disabled) &&
                    states.contains(WidgetState.selected)
                ? colors.primaryContainer
                : null),
        foregroundColor: WidgetStateProperty.resolveWith((states) =>
            !states.contains(WidgetState.disabled) &&
                    states.contains(WidgetState.selected)
                ? colors.onPrimaryContainer
                : null),
      ),
    ),
    chipTheme: ChipThemeData(
      selectedColor: colors.primaryContainer,
      checkmarkColor: colors.onPrimaryContainer,
    ),
    inputDecorationTheme: InputDecorationTheme(
      labelStyle: const TextStyle(color: secondaryInk),
      hintStyle: const TextStyle(color: secondaryInk),
      helperStyle: const TextStyle(color: secondaryInk, fontSize: 14),
      errorStyle: TextStyle(color: colors.error, fontSize: 14),
      enabledBorder:
          UnderlineInputBorder(borderSide: BorderSide(color: colors.outline)),
      focusedBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: colors.primary, width: 2)),
    ),
    filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
      disabledForegroundColor: secondaryInk,
      disabledBackgroundColor: colors.surfaceContainerHighest,
      minimumSize: const Size(0, 48),
    )),
    outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
      disabledForegroundColor: secondaryInk,
      side: BorderSide(color: colors.outline),
      minimumSize: const Size(0, 48),
    )),
    textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
      disabledForegroundColor: secondaryInk,
      minimumSize: const Size(0, 48),
    )),
  );
}
