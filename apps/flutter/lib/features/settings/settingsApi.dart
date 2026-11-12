import "../../core/apiClient.dart";

/// 设备配对成功后的返回数据。
class PairResult {
  final String deviceToken;
  final String hostName;

  const PairResult({required this.deviceToken, required this.hostName});

  factory PairResult.fromJson(Map<String, dynamic> json) => PairResult(
        deviceToken: json["deviceToken"] as String,
        hostName: json["name"] as String? ?? "",
      );
}

/// MCP 服务器条目（移动端只读展示）。
class McpServer {
  final String id;
  final String name;
  final String transport;
  final bool enabled;
  final String status;
  final int toolCount;

  const McpServer({
    required this.id,
    required this.name,
    required this.transport,
    required this.enabled,
    required this.status,
    required this.toolCount,
  });

  factory McpServer.fromJson(Map<String, dynamic> json) => McpServer(
        id: json["id"] as String? ?? "",
        name: json["name"] as String? ?? "",
        transport: json["transport"] as String? ?? "",
        enabled: json["enabled"] as bool? ?? false,
        status: json["status"] as String? ?? "",
        toolCount: json["toolCount"] as int? ?? 0,
      );
}

/// 设置页涉及的远程接口：设备配对与 MCP 服务器只读列表。
///
/// ACT: 移动端只做设备配对与只读浏览；插件安装、skill 编辑、ffmpeg 下载、
/// MCP 导入等管理操作是桌面端专属，此处不提供对应封装。
class SettingsApi {
  final ApiClient client;

  SettingsApi(this.client);

  Future<PairResult> pair(String code, String name) async {
    final data = await client.request(
      "POST",
      "/api/mobileLink/pair",
      body: {"code": code, "name": name},
    ) as Map<String, dynamic>;
    return PairResult.fromJson(data);
  }

  Future<List<McpServer>> listMcpServers() async {
    final data = await client.getData("/api/mcp/servers/list") as Map<String, dynamic>;
    final servers = (data["servers"] as List? ?? const [])
        .map((e) => McpServer.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    return servers;
  }
}
