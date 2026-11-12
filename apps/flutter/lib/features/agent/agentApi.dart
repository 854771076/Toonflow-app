import "../../core/apiClient.dart";
import "../../core/config.dart";
import "agentTypes.dart";

/// Agent 会话、模型、技能与提及接口封装，统一携带工作区契约 header。
class AgentApi {
  final ApiClient client;
  final String directory;

  const AgentApi({required this.client, required this.directory});

  /// 工作区契约 header。
  Map<String, String> get headers => {ServerFields.workspaceHeader: "1"};

  Future<List<AgentModel>> listModels() async {
    final data = await client.request("GET", "/api/ai/models", headers: headers);
    return (data as List? ?? const [])
        .whereType<Map>()
        .map((e) => AgentModel.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<List<AgentSession>> listSessions() async {
    final data = await client.request(
      "GET",
      "/api/agent/list",
      query: {"directory": directory},
      headers: headers,
    );
    return (data as List? ?? const [])
        .whereType<Map>()
        .map((e) => AgentSession.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<AgentSession> createSession() async {
    final data = await client.request(
      "POST",
      "/api/agent/create",
      body: {"directory": directory},
      headers: headers,
      contentType: "application/json",
    );
    return AgentSession.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<List<AgentMessage>> getSession(String sessionFile) async {
    final data = await client.request(
      "GET",
      "/api/agent/get",
      query: {"directory": directory, "sessionFile": sessionFile},
      headers: headers,
    );
    final map = Map<String, dynamic>.from(data as Map);
    final messages = map["messages"] as List? ?? const [];
    return messages
        .whereType<Map>()
        .map((e) => AgentMessage.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<void> renameSession(String sessionFile, String name) async {
    await client.request(
      "PATCH",
      "/api/agent/rename",
      body: {"directory": directory, "sessionFile": sessionFile, "name": name},
      headers: headers,
      contentType: "application/json",
    );
  }

  Future<void> stopRuns(List<String> runIds) async {
    await client.request(
      "POST",
      "/api/agent/stop",
      body: {"directory": directory, "runIds": runIds},
      headers: headers,
      contentType: "application/json",
    );
  }

  Future<List<AgentSkill>> listSkills() async {
    final data = await client.request(
      "GET",
      "/api/agent/skills",
      query: {"directory": directory},
      headers: headers,
    );
    return (data as List? ?? const [])
        .whereType<Map>()
        .map((e) => AgentSkill.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<List<AgentAsset>> listAssets({String path = ""}) async {
    final query = <String, dynamic>{"directory": directory, "operation": "assets"};
    if (path.isNotEmpty) query["path"] = path;
    final data = await client.request(
      "GET",
      "/api/agent/mentionSource",
      query: query,
      headers: headers,
    );
    final map = Map<String, dynamic>.from(data as Map);
    final items = map["items"] as List? ?? const [];
    return items
        .whereType<Map>()
        .map((e) => AgentAsset.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<AgentMention> selectAsset(String path) async {
    final data = await client.request(
      "GET",
      "/api/agent/mentionSource",
      query: {"directory": directory, "operation": "selectAsset", "path": path},
      headers: headers,
    );
    return AgentMention.fromJson(Map<String, dynamic>.from(data as Map));
  }
}
