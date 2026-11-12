import "package:flutter/material.dart";

/// 设计令牌：与 web 端主题对齐（主题色 #409EFF、圆角 8px、默认深色）。
class DesignTokens {
  DesignTokens._();

  /// 主题色，默认 0xFF409EFF。
  static const Color primary = Color(0xFF409EFF);

  /// 圆角半径：小 4px。
  static const double radiusSmall = 4;

  /// 圆角半径：medium 8px（沿用原名 radius 作为中号）。
  static const double radius = 8;

  /// 圆角半径：大 12px。
  static const double radiusLarge = 12;

  /// 间距。
  static const double spaceXs = 4;
  static const double spaceSm = 8;
  static const double spaceMd = 12;
  static const double spaceLg = 16;
  static const double spaceXl = 24;

  /// 字体缩放百分比，默认 100（与 web 端一致）。
  static const double fontScale = 100;

  /// 浅色：背景。
  static const Color backgroundLight = Color(0xFFF5F7FA);

  /// 浅色：表面/卡片。
  static const Color surfaceLight = Color(0xFFFFFFFF);

  /// 浅色：文字主色。
  static const Color textPrimaryLight = Color(0xFF303133);

  /// 浅色：文字次色。
  static const Color textSecondaryLight = Color(0xFF909399);

  /// 浅色：边框。
  static const Color borderLight = Color(0xFFDCDFE6);

  /// 深色：背景。
  static const Color backgroundDark = Color(0xFF0A0A0A);

  /// 深色：表面/卡片。
  static const Color surfaceDark = Color(0xFF1D1E1F);

  /// 深色：文字主色。
  static const Color textPrimaryDark = Color(0xFFE5EAF3);

  /// 深色：文字次色。
  static const Color textSecondaryDark = Color(0xFFA3A6AD);

  /// 深色：边框。
  static const Color borderDark = Color(0xFF4C4D4F);
}
