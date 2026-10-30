import 'package:flutter/material.dart';

ThemeData buildEasyCheckTheme() {
  const ink = Color(0xFF1D2939);
  const secondaryInk = Color(0xFF475467);
  const background = Color(0xFFF8FAFC);
  final colors = ColorScheme.fromSeed(
    seedColor: const Color(0xFF2457A6),
    brightness: Brightness.light,
    primary: const Color(0xFF2457A6),
    onPrimary: Colors.white,
    primaryContainer: const Color(0xFFE4EDFC),
    onPrimaryContainer: const Color(0xFF173B73),
    surface: background,
    onSurface: ink,
    onSurfaceVariant: secondaryInk,
    surfaceContainerLow: Colors.white,
    surfaceContainerHighest: const Color(0xFFEAECF0),
    outline: const Color(0xFF667085),
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
