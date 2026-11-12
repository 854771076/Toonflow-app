/// 应用全局配置与常量。
///
/// 客户端源码不出现任何产品名残留。服务端 API 返回数据里的契约字段
/// 集中在 [ServerFields]，以常量引用并注明「服务端契约字段」。
class AppConfig {
  /// 应用显示名。
  static const String appName = "YuYuer Drama";

  /// 默认服务端地址，可被用户在登录页覆盖并持久化。
  static const String defaultBaseUrl = "http://127.0.0.1:3100";

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
