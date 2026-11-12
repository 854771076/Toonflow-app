import "package:shared_preferences/shared_preferences.dart";

import "config.dart";

/// 会话、服务端地址、语言与主题的本地持久化。
class SessionStore {
  static Future<String> getBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(AppConfig.baseUrlKey) ?? AppConfig.defaultBaseUrl;
  }

  static Future<void> saveBaseUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConfig.baseUrlKey, url);
  }

  static Future<String?> getSession() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(AppConfig.sessionKey);
  }

  static Future<void> saveSession(String? cookie) async {
    final prefs = await SharedPreferences.getInstance();
    if (cookie == null || cookie.isEmpty) {
      await prefs.remove(AppConfig.sessionKey);
    } else {
      await prefs.setString(AppConfig.sessionKey, cookie);
    }
  }

  /// 界面语言代码（如 zh_CN、en），未设置或 "system" 表示跟随系统。
  static Future<String> getLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(AppConfig.languageKey) ?? "system";
  }

  static Future<void> saveLanguage(String code) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConfig.languageKey, code);
  }

  /// 主题模式（light / dark / system），默认 dark。
  static Future<String> getThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(AppConfig.themeKey) ?? "dark";
  }

  static Future<void> saveThemeMode(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConfig.themeKey, mode);
  }

  /// 已配对设备 token；未配对时为 null。
  static Future<String?> getDeviceToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(AppConfig.deviceTokenKey);
  }

  static Future<void> saveDeviceToken(String? token) async {
    final prefs = await SharedPreferences.getInstance();
    if (token == null || token.isEmpty) {
      await prefs.remove(AppConfig.deviceTokenKey);
    } else {
      await prefs.setString(AppConfig.deviceTokenKey, token);
    }
  }

  /// 已配对设备名称；未配对时为 null。
  static Future<String?> getDeviceName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(AppConfig.deviceNameKey);
  }

  static Future<void> saveDeviceName(String? name) async {
    final prefs = await SharedPreferences.getInstance();
    if (name == null || name.isEmpty) {
      await prefs.remove(AppConfig.deviceNameKey);
    } else {
      await prefs.setString(AppConfig.deviceNameKey, name);
    }
  }
}
