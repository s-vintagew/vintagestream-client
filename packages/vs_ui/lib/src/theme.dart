import 'package:flutter/material.dart';

class VsTheme {
  static const brandRed = Color(0xFFE50914);
  static const scaffold = Color(0xFF0B0B0D);
  static const card = Color(0xFF16161A);
  static const muted = Color(0xFF9A9AA3);

  static ThemeData dark() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: brandRed,
        brightness: Brightness.dark,
        primary: brandRed,
        surface: scaffold,
      ),
      scaffoldBackgroundColor: scaffold,
      appBarTheme: const AppBarTheme(
        backgroundColor: scaffold,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: card,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        hintStyle: const TextStyle(color: muted),
      ),
    );
    return base.copyWith(
      textTheme: base.textTheme.apply(
        bodyColor: Colors.white,
        displayColor: Colors.white,
      ),
    );
  }
}
