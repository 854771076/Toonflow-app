import "dart:convert";

import "apiClient.dart";
import "config.dart";

/// 工作区文件操作统一入口。
///
/// 所有请求自动携带工作区契约 header，目录固定为构造时传入的绝对路径。
class WorkspaceFiles {
  final ApiClient client;
  final String directory;

  WorkspaceFiles({required this.client, required this.directory});

  Map<String, String> get _workspaceHeaders => {
    ServerFields.workspaceHeader: "1",
  };

  Future<Map<String, dynamic>> list(String path) async {
    final data = await client.request(
      "GET",
      "/api/workspaces/files/list",
      query: {"directory": directory, "path": path},
      headers: _workspaceHeaders,
    );
    return Map<String, dynamic>.from(data as Map);
  }

  Future<String> readText(String path) async {
    final data = await client.request(
      "GET",
      "/api/workspaces/files/read",
      query: {"directory": directory, "path": path, "snapshot": "true"},
      headers: _workspaceHeaders,
    );
    return Map<String, dynamic>.from(data as Map)["text"] as String? ?? "";
  }

  Future<dynamic> readJson(String path) async {
    return jsonDecode(await readText(path));
  }

  Future<void> writeText(
    String path,
    String content, {
    bool exclusive = false,
  }) async {
    await client.request(
      "PUT",
      "/api/workspaces/files/write",
      query: {"directory": directory, "path": path, "exclusive": "$exclusive"},
      body: content,
      headers: _workspaceHeaders,
      contentType: "application/octet-stream",
    );
  }
}
