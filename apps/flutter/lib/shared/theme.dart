import "package:flutter/material.dart";
import "package:forui/forui.dart";

import "designTokens.dart";

/// 应用主题：light/dark 由 [AppTheme.light] / [AppTheme.dark] 提供，
/// system 三态由 MaterialApp.themeMode 控制，默认 dark。
///
/// Material 主题（[AppTheme.light]/[AppTheme.dark]）用于 MaterialApp 外壳与
/// 少量残留 Material 组件；Forui 主题（[AppTheme.foruiLight]/[AppTheme.foruiDark]）
/// 供 FTheme 消费，主色对齐 web 端 #409EFF、危险色对齐 #F56C6C，背景/卡片/文字/边框
/// 对齐 DesignTokens。
class AppTheme {
  static ThemeData light() => _buildMaterial(
        brightness: Brightness.light,
        background: DesignTokens.backgroundLight,
        surface: DesignTokens.surfaceLight,
        textPrimary: DesignTokens.textPrimaryLight,
        textSecondary: DesignTokens.textSecondaryLight,
        border: DesignTokens.borderLight,
      );

  static ThemeData dark() => _buildMaterial(
        brightness: Brightness.dark,
        background: DesignTokens.backgroundDark,
        surface: DesignTokens.surfaceDark,
        textPrimary: DesignTokens.textPrimaryDark,
        textSecondary: DesignTokens.textSecondaryDark,
        border: DesignTokens.borderDark,
      );

  static FThemeData foruiLight() => _buildForui(FColors.neutralLight, isDark: false);

  static FThemeData foruiDark() => _buildForui(FColors.neutralDark, isDark: true);

  static ThemeData _buildMaterial({
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
    ).copyWith(
      primary: DesignTokens.primary,
      onPrimary: Colors.white,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: background,
      cardTheme: CardThemeData(
        elevation: 1,
        shadowColor: DesignTokens.shadowCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
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
        errorStyle: TextStyle(color: DesignTokens.danger),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radius),
          borderSide: BorderSide(color: DesignTokens.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radius),
          borderSide: BorderSide(color: DesignTokens.danger, width: 2),
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

  static FThemeData _buildForui(FColors base, {required bool isDark}) {
    return FThemeData(
      touch: true,
      colors: base.copyWith(
        primary: DesignTokens.primary,
        primaryForeground: Colors.white,
        background: isDark ? DesignTokens.backgroundDark : DesignTokens.backgroundLight,
        foreground: isDark ? DesignTokens.textPrimaryDark : DesignTokens.textPrimaryLight,
        card: isDark ? DesignTokens.surfaceDark : DesignTokens.surfaceLight,
        border: isDark ? DesignTokens.borderDark : DesignTokens.borderLight,
        destructive: DesignTokens.danger,
        destructiveForeground: Colors.white,
        error: DesignTokens.danger,
        errorForeground: Colors.white,
      ),
    );
  }
}
