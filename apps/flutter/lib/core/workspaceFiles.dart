import "dart:convert";
import "dart:typed_data";

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

  Future<Uint8List> readBytes(String path) async {
    return client.getBytes(
      "/api/workspaces/files/read",
      query: {"directory": directory, "path": path},
      headers: _workspaceHeaders,
    );
  }

  /// 打包导出整个工作区为 ZIP，返回 ZIP 文件字节。
  Future<Uint8List> exportZip() async {
    return client.getBytes(
      "/api/workspaces/files/export",
      query: {"directory": directory},
      headers: _workspaceHeaders,
    );
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

  Future<void> writeJson(
    String path,
    Map<String, dynamic> data, {
    bool exclusive = false,
  }) => writeText(path, jsonEncode(data), exclusive: exclusive);

  Future<void> mkdir(String path) async {
    await client.request(
      "POST",
      "/api/workspaces/files/mkdir",
      body: {"directory": directory, "path": path},
      headers: _workspaceHeaders,
    );
  }

  Future<void> rename(String path, String target) async {
    await client.request(
      "POST",
      "/api/workspaces/files/rename",
      body: {"directory": directory, "path": path, "target": target},
      headers: _workspaceHeaders,
    );
  }

  Future<void> remove(String path, [bool recursive = false]) async {
    await client.request(
      "DELETE",
      "/api/workspaces/files/remove",
      body: {"directory": directory, "path": path, "recursive": recursive},
      headers: _workspaceHeaders,
    );
  }
}
