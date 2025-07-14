import 'package:flutter/material.dart';

class AppTheme {
  static const Color background = Color(0xFF121212); // almost black
  static const Color surface = Color(0xFF1E1E1E); // dark grey
  static const Color primary = Color(0xFFFFC857); // yellow accent
  static const Color onPrimary = Colors.black;
  static const Color text = Colors.white70;

  static final ThemeData darkTheme = ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: background,
    appBarTheme: const AppBarTheme(
      backgroundColor: surface,
      foregroundColor: text,
      elevation: 0,
    ),
    colorScheme: ColorScheme.dark(
      primary: primary,
      secondary: primary,
      background: background,
      surface: surface,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: onPrimary,
        textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    textTheme: const TextTheme(
      bodyLarge: TextStyle(color: text, fontSize: 18),
      bodyMedium: TextStyle(color: text, fontSize: 16),
      titleLarge: TextStyle(
        color: text,
        fontSize: 22,
        fontWeight: FontWeight.bold,
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(10)),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: primary),
        borderRadius: BorderRadius.all(Radius.circular(10)),
      ),
      labelStyle: TextStyle(color: text),
    ),
  );
}
