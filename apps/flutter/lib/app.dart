import "package:flutter/material.dart";
import "package:forui/forui.dart";

import "core/apiClient.dart";
import "core/authService.dart";
import "core/config.dart";
import "core/sessionStore.dart";
import "features/auth/loginPage.dart";
import "features/home/projectListPage.dart";
import "shared/appLocalizations.dart";
import "shared/theme.dart";

/// 应用根组件：初始化会话并按登录态切换登录页 / 项目列表页。
class YuYuerApp extends StatefulWidget {
  const YuYuerApp({super.key});

  @override
  State<YuYuerApp> createState() => _YuYuerAppState();
}

class _YuYuerAppState extends State<YuYuerApp> {
  /// 界面语言；为 null 时跟随系统。
  Locale? _locale;
  ThemeMode _themeMode = ThemeMode.dark;

  ApiClient? _client;
  AuthService? _auth;
  bool _checking = true;
  bool _loggedIn = false;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final baseUrl = await SessionStore.getBaseUrl();
    final session = await SessionStore.getSession();
    final language = await SessionStore.getLanguage();
    final themeMode = await SessionStore.getThemeMode();
    final deviceToken = await SessionStore.getDeviceToken();
    final client = ApiClient(baseUrl: baseUrl);
    client.setSession(session);
    client.setDeviceToken(deviceToken);
    client.onSessionExpired = _handleSessionExpired;

    var loggedIn = false;
    if (session != null && session.isNotEmpty) {
      try {
        loggedIn = (await AuthService(client).session()).authenticated;
      } catch (_) {
        // 会话校验失败按未登录处理。
      }
      if (!loggedIn) {
        client.setSession(null);
        await SessionStore.saveSession(null);
      }
    }

    if (!mounted) return;
    setState(() {
      _locale = _localeFromString(language);
      _themeMode = _themeModeFromString(themeMode);
      _client = client;
      _auth = AuthService(client);
      _loggedIn = loggedIn;
      _checking = false;
    });
  }

  Future<void> _onLoggedIn() async {
    final baseUrl = await SessionStore.getBaseUrl();
    final session = await SessionStore.getSession();
    final deviceToken = await SessionStore.getDeviceToken();
    final client = ApiClient(baseUrl: baseUrl);
    client.setSession(session);
    client.setDeviceToken(deviceToken);
    client.onSessionExpired = _handleSessionExpired;
    setState(() {
      _client = client;
      _auth = AuthService(client);
      _loggedIn = true;
    });
  }

  Future<void> _onLoggedOut() async {
    await SessionStore.saveSession(null);
    _client?.setSession(null);
    setState(() => _loggedIn = false);
  }

  /// 会话运行中失效（服务端返回 401）时清空会话并回到登录页。
  void _handleSessionExpired() {
    SessionStore.saveSession(null);
    _client?.setSession(null);
    if (mounted) setState(() => _loggedIn = false);
  }

  /// 设置主题模式（供后续设置页使用）。
  Future<void> setThemeMode(ThemeMode mode) async {
    setState(() => _themeMode = mode);
    await SessionStore.saveThemeMode(mode.name);
  }

  /// 设置界面语言；code 为 "system" 时跟随系统。
  Future<void> setLocale(String code) async {
    setState(() => _locale = _localeFromString(code));
    await SessionStore.saveLanguage(code);
  }

  /// 在中文 / 英文间循环切换，保持入口可用（后续由语言选择 UI 取代）。
  Future<void> _toggleLanguage() async {
    final isZh = _locale?.languageCode == "zh";
    await setLocale(isZh ? "en" : "zh_CN");
  }

  Locale? _localeFromString(String code) {
    if (code.isEmpty || code == "system") return null;
    final parts = code.split("_");
    if (parts.length >= 2) return Locale(parts[0], parts[1]);
    return Locale(parts[0]);
  }

  ThemeMode _themeModeFromString(String mode) {
    switch (mode) {
      case "light":
        return ThemeMode.light;
      case "system":
        return ThemeMode.system;
      default:
        return ThemeMode.dark;
    }
  }

  /// 跟随系统时解析平台语言到支持列表，未匹配时回退英文。
  Locale _resolveLocale(Locale? locale, Iterable<Locale> supportedLocales) {
    if (locale == null) return const Locale("en");
    for (final supported in supportedLocales) {
      if (supported.languageCode == locale.languageCode &&
          supported.countryCode == locale.countryCode) {
        return supported;
      }
    }
    for (final supported in supportedLocales) {
      if (supported.languageCode == locale.languageCode) return supported;
    }
    return const Locale("en");
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: _themeMode,
      locale: _locale,
      localeResolutionCallback: _resolveLocale,
      localizationsDelegates: [
        ...AppLocalizations.localizationsDelegates,
        ...FLocalizations.localizationsDelegates,
      ],
      supportedLocales: [
        ...AppLocalizations.supportedLocales,
        ...FLocalizations.supportedLocales,
      ],
      builder: (context, child) {
        final isDark = _themeMode == ThemeMode.dark ||
            (_themeMode == ThemeMode.system &&
                MediaQuery.platformBrightnessOf(context) == Brightness.dark);
        return FTheme(
          data: isDark ? AppTheme.foruiDark() : AppTheme.foruiLight(),
          // forui 的 FScaffold 不提供 Material 祖先，而页面内混用了 TextField、
          // InkWell、ListTile 等 Material 组件，缺少 Material 会报
          // "No Material widget found"；这里统一补一层透明 Material。
          child: Material(
            type: MaterialType.transparency,
            child: FToaster(child: FTooltipGroup(child: child!)),
          ),
        );
      },
      home: _buildHome(),
      // Supabase OAuth 深链回跳 yuyuer://auth/callback 会被 Flutter Navigator
      // 当作命名路由 push；实际由 supabase_flutter 的 app_links 通道处理，
      // 这里返回空占位页面，避免 "Could not find a generator for route" 报错。
      onGenerateRoute: (settings) {
        if (settings.name?.startsWith("/callback") == true) {
          return MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => const SizedBox.shrink(),
          );
        }
        return null;
      },
    );
  }

  Widget _buildHome() {
    if (_checking || _client == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!_loggedIn) {
      return LoginPage(
        client: _client!,
        onLoggedIn: _onLoggedIn,
        onToggleLanguage: _toggleLanguage,
        onLocaleChanged: setLocale,
        onThemeModeChanged: (mode) => setThemeMode(_themeModeFromString(mode)),
      );
    }
    return ProjectListPage(
      client: _client!,
      auth: _auth!,
      onLoggedOut: _onLoggedOut,
      onToggleLanguage: _toggleLanguage,
      onLocaleChanged: setLocale,
      onThemeModeChanged: (mode) => setThemeMode(_themeModeFromString(mode)),
    );
  }
}
