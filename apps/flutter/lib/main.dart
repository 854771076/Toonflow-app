import "package:flutter/material.dart";
import "package:supabase_flutter/supabase_flutter.dart";

import "app.dart";
import "core/apiClient.dart";
import "core/config.dart";
import "core/sessionStore.dart";

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Supabase 配置优先取服务端 settings.json（持久化配置），取不到时回退编译期默认值。
  var supabaseUrl = AppConfig.supabaseUrl;
  var supabaseAnonKey = AppConfig.supabaseAnonKey;
  try {
    final baseUrl = await SessionStore.getBaseUrl();
    final config = await ApiClient(baseUrl: baseUrl).request(
      "GET",
      "/api/auth/supabase",
    ) as Map<String, dynamic>;
    final url = config["supabaseUrl"];
    final key = config["supabaseAnonKey"];
    if (url is String && url.isNotEmpty) supabaseUrl = url;
    if (key is String && key.isNotEmpty) supabaseAnonKey = key;
  } catch (_) {
    // 服务端不可达或未返回 Supabase 配置时，回退默认值。
  }
  if (supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty) {
    await Supabase.initialize(
      url: supabaseUrl,
      publishableKey: supabaseAnonKey,
    );
  }
  runApp(const YuYuerApp());
}
