import "dart:convert";

import "package:shared_preferences/shared_preferences.dart";

import "config.dart";

/// 一个项目，对应服务端工作区目录。
class Project {
  final String directory;
  final String name;
  final DateTime lastOpenedAt;

  Project({required this.directory, required this.name, required this.lastOpenedAt});

  Map<String, dynamic> toJson() => {
        "directory": directory,
        "name": name,
        "lastOpenedAt": lastOpenedAt.toIso8601String(),
      };

  static Project fromJson(Map<String, dynamic> json) => Project(
        directory: json["directory"] as String,
        name: json["name"] as String,
        lastOpenedAt: DateTime.tryParse(json["lastOpenedAt"] as String? ?? "") ?? DateTime.now(),
      );
}

/// 项目列表本地持久化（对齐 web 端本地保存的项目列表）。
class ProjectStore {
  static Future<List<Project>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(AppConfig.projectsKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => Project.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> save(List<Project> projects) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(projects.map((e) => e.toJson()).toList());
    await prefs.setString(AppConfig.projectsKey, raw);
  }
}
