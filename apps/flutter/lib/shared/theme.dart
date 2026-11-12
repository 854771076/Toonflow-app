import "package:flutter/material.dart";

import "designTokens.dart";

/// 应用主题：light/dark 由 [AppTheme.light] / [AppTheme.dark] 提供，
/// system 三态由 MaterialApp.themeMode 控制，默认 dark。
class AppTheme {
  static ThemeData light() => _build(
        brightness: Brightness.light,
        background: DesignTokens.backgroundLight,
        surface: DesignTokens.surfaceLight,
        textPrimary: DesignTokens.textPrimaryLight,
        textSecondary: DesignTokens.textSecondaryLight,
        border: DesignTokens.borderLight,
      );

  static ThemeData dark() => _build(
        brightness: Brightness.dark,
        background: DesignTokens.backgroundDark,
        surface: DesignTokens.surfaceDark,
        textPrimary: DesignTokens.textPrimaryDark,
        textSecondary: DesignTokens.textSecondaryDark,
        border: DesignTokens.borderDark,
      );

  static ThemeData _build({
    required Brightness brightness,
    required Color background,
    required Color surface,
    required Color textPrimary,
    required Color textSecondary,
    required Color border,
  }) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: DesignTokens.primary,
      brightness: brightness,
    ).copyWith(
      surface: surface,
      onSurface: textPrimary,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: background,
      cardTheme: CardThemeData(
        elevation: 1,
        shadowColor: const Color(0x14000000),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusLarge),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        foregroundColor: textPrimary,
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        labelStyle: TextStyle(color: textSecondary),
        hintStyle: TextStyle(color: textSecondary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radius),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radius),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radius),
          borderSide: BorderSide(color: DesignTokens.primary, width: 2),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DesignTokens.radius),
          ),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: border,
        thickness: 1,
      ),
    );
  }
}
