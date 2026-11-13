/// 应用全局配置与常量。
///
/// 客户端源码不出现任何产品名残留。服务端 API 返回数据里的契约字段
/// 集中在 [ServerFields]，以常量引用并注明「服务端契约字段」。
class AppConfig {
  /// 应用显示名。
  static const String appName = "YuYuer Drama";

  /// 默认服务端地址，可被用户在登录页覆盖并持久化。
  /// 通过 `--dart-define=API_BASE_URL=...` 注入，未注入时回退本地开发地址。
  static const String defaultBaseUrl = String.fromEnvironment(
    "API_BASE_URL",
    defaultValue: "http://127.0.0.1:3100",
  );

  /// Supabase 项目地址（登录用）。优先取服务端 settings.json，其次 `--dart-define=SUPABASE_URL=...`，最后回退开发项目地址。
  static const String supabaseUrl = String.fromEnvironment(
    "SUPABASE_URL",
    defaultValue: "https://jknkenfhhwpxwwgqmcxv.supabase.co",
  );

  /// Supabase 匿名公钥（登录用）。优先取服务端 settings.json，其次 `--dart-define=SUPABASE_ANON_KEY=...`，最后回退开发公钥。
  static const String supabaseAnonKey = String.fromEnvironment(
    "SUPABASE_ANON_KEY",
    defaultValue: "sb_publishable_Y1bDLtBvaQktz_na-W9o_A_sxB5NfTO",
  );

  /// OAuth 深链 scheme，与 AndroidManifest.xml、Info.plist 保持一致。
  static const String authScheme = "yuyuer";

  /// 本地持久化键：服务端地址。
  static const String baseUrlKey = "yuyuer.baseUrl";

  /// 本地持久化键：会话 cookie 值。
  static const String sessionKey = "yuyuer.session";

  /// 本地持久化键：项目列表 JSON。
  static const String projectsKey = "yuyuer.projects";

  /// 本地持久化键：界面语言代码（或 "system" 表示跟随系统）。
  static const String languageKey = "yuyuer.language";

  /// 本地持久化键：主题模式（light / dark / system）。
  static const String themeKey = "yuyuer.theme";

  /// 本地持久化键：已配对设备的 token。
  static const String deviceTokenKey = "yuyuer.deviceToken";

  /// 本地持久化键：已配对设备的名称。
  static const String deviceNameKey = "yuyuer.deviceName";

  /// 客户端版本号，随设备请求头一并发送。
  static const String appVersion = "1.0.0";
}

/// 服务端 API 契约字段。
///
/// 这些字段名来自服务端返回的数据结构，属于服务端契约，
/// 客户端仅以常量引用，不代表客户端品牌。
class ServerFields {
  /// 画布文件标记字段（服务端/画布 JSON 契约）。
  static const String canvasMark = "toonflowCanvas";

  /// 工作区文件接口请求头（服务端契约）。
  static const String workspaceHeader = "x-toonflow-workspace";

  /// 已配对设备 token 请求头（服务端契约）。
  static const String deviceTokenHeader = "x-toonflow-device-token";

  /// 客户端版本请求头（服务端契约）。
  static const String appVersionHeader = "x-toonflow-app-version";
}
