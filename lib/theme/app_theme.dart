import 'package:flutter/material.dart';
import 'colors.dart';

/// Centralized application ThemeData definitions.
class AppTheme {
  AppTheme._();

  static ThemeData get dark {
    final base = ThemeData.dark();
    return base.copyWith(
      scaffoldBackgroundColor: backgroundDark,
      colorScheme: base.colorScheme.copyWith(
  primary: newaccent,
        secondary: accentTech,
      ),
      textTheme: base.textTheme.apply(fontFamily: 'Inter'),
      dividerColor: borderDark,
      dialogTheme: const DialogThemeData(backgroundColor: surfaceDark),
      // Remove ripple/splash and pressed overlay effects globally
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      splashColor: Colors.transparent,
      hoverColor: Colors.transparent,
      // Remove pressed/hover overlays for buttons as well
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          splashFactory: NoSplash.splashFactory,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          splashFactory: NoSplash.splashFactory,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          splashFactory: NoSplash.splashFactory,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          splashFactory: NoSplash.splashFactory,
        ),
      ),
      // Default to borderless inputs; components that want outlines provide
      // their own InputDecoration with OutlineInputBorder.
      inputDecorationTheme: const InputDecorationTheme(
        isDense: true,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
      ),
    );
  }
}
