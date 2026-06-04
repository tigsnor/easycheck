import 'package:flutter/material.dart';

ThemeData buildEasyCheckTheme() {
  const noteYellow = Color(0xFFFFCC33);
  const ink = Color(0xFF1C1C1E);
  const background = Color(0xFFF7F7F2);

  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: noteYellow,
      primary: noteYellow,
      onPrimary: ink,
      surface: background,
    ),
    scaffoldBackgroundColor: background,
    appBarTheme: const AppBarTheme(
      backgroundColor: background,
      foregroundColor: ink,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: ink,
        fontSize: 28,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}
