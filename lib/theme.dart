import 'package:flutter/material.dart';

abstract final class AppColors {
  static const background = Color(0xFF0B0B10);
  static const surface = Color(0xFF15151C);
  static const button = Color(0xFF1F1F28);
  static const buttonPressed = Color(0xFF2C2C38);
  static const accent = Color(0xFF0A84FF);
  static const online = Color(0xFF30D158);
  static const offline = Color(0xFFFF453A);
  static const text = Color(0xFFF2F2F7);
  static const textDim = Color(0xFF98989F);

  static ThemeData dark() => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: background,
        colorScheme: const ColorScheme.dark(
          primary: accent,
          surface: surface,
          onSurface: text,
        ),
        snackBarTheme: const SnackBarThemeData(backgroundColor: surface),
        dialogTheme: const DialogThemeData(backgroundColor: surface),
      );
}
