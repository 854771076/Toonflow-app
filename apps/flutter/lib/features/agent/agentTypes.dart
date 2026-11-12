// Agent 对话相关数据模型与 JSON 解析。

/// 语言模型（来自 `/api/ai/models`）。
class AgentModel {
  final String providerId;
  final String providerLabel;
  final String modelId;
  final String label;

  const AgentModel({
    required this.providerId,
    required this.providerLabel,
    required this.modelId,
    required this.label,
  });

  factory AgentModel.fromJson(Map<String, dynamic> json) => AgentModel(
        providerId: json["providerId"] as String? ?? "",
        providerLabel: json["providerLabel"] as String? ?? "",
        modelId: json["modelId"] as String? ?? "",
        label: json["label"] as String? ?? "",
      );

  String get displayLabel {
    if (providerLabel.isEmpty) return label.isEmpty ? modelId : label;
    return "$providerLabel · $label";
  }
}

/// 会话摘要（列表项）。
class AgentSession {
  final String file;
  final String name;
  final int messageCount;

  const AgentSession({
    required this.file,
    required this.name,
    required this.messageCount,
  });

  factory AgentSession.fromJson(Map<String, dynamic> json) => AgentSession(
        file: json["file"] as String? ?? "",
        name: json["name"] as String? ?? "",
        messageCount: json["messageCount"] is int ? json["messageCount"] as int : 0,
      );
}

/// 工具调用（助手消息中的工具块）。
class AgentTool {
  final String id;
  final String name;
  final String status;
  String result;

  AgentTool({
    required this.id,
    required this.name,
    required this.status,
    this.result = "",
  });

  factory AgentTool.fromJson(Map<String, dynamic> json) => AgentTool(
        id: json["id"] as String? ?? "",
        name: json["name"] as String? ?? "",
        status: json["status"] as String? ?? "running",
        result: json["result"] as String? ?? "",
      );
}

/// 助手消息中的一个渲染块：文本、思考或工具调用。
class AgentPart {
  final String type; // text / thinking / tool
  final String blockId;
  String content;
  bool collapsed;
  AgentTool? tool;

  AgentPart.text({required this.blockId, required this.content})
      : type = "text",
        collapsed = false,
        tool = null;

  AgentPart.thinking({required this.blockId, required this.content})
      : type = "thinking",
        collapsed = true,
        tool = null;

  AgentPart.tool(AgentTool call)
      : type = "tool",
        blockId = call.id,
        content = "",
        collapsed = false,
        tool = call;

  factory AgentPart.fromJson(Map<String, dynamic> json) {
    final type = json["type"] as String? ?? "text";
    if (type == "tool") {
      final toolJson = json["tool"];
      return AgentPart.tool(AgentTool.fromJson(
        toolJson is Map ? Map<String, dynamic>.from(toolJson) : const {},
      ));
    }
    final part = type == "thinking"
        ? AgentPart.thinking(
            blockId: json["id"] as String? ?? "",
            content: json["content"] as String? ?? "",
          )
        : AgentPart.text(
            blockId: json["id"] as String? ?? "",
            content: json["content"] as String? ?? "",
          );
    part.collapsed = json["collapsed"] == true;
    return part;
  }
}

/// 单条对话消息（用户或助手）。
class AgentMessage {
  final String role; // user / assistant
  String content;
  String? error;
  final List<AgentPart> parts;
  bool streaming;

  AgentMessage.user(this.content)
      : role = "user",
        error = null,
        parts = [],
        streaming = false;

  AgentMessage.assistant({this.streaming = true})
      : role = "assistant",
        content = "",
        error = null,
        parts = [];

  factory AgentMessage.fromJson(Map<String, dynamic> json) {
    final role = json["role"] as String? ?? "user";
    final content = json["content"] as String? ?? "";
    final parts = (json["parts"] as List? ?? const [])
        .whereType<Map>()
        .map((p) => AgentPart.fromJson(Map<String, dynamic>.from(p)))
        .toList();
    if (role == "assistant") {
      final message = AgentMessage.assistant(streaming: json["streaming"] == true);
      message.content = content;
      message.error = json["error"] as String?;
      message.parts.addAll(parts);
      return message;
    }
    return AgentMessage.user(content);
  }

  bool get isUser => role == "user";
}

/// 资产提及（仅支持 asset 来源）。
class AgentMention {
  final String id;
  final String label;
  final String path;
  final String dataType;
  final dynamic value;

  const AgentMention({
    required this.id,
    required this.label,
    required this.path,
    required this.dataType,
    this.value,
  });

  factory AgentMention.fromJson(Map<String, dynamic> json) {
    final source = json["source"];
    final sourceMap =
        source is Map ? Map<String, dynamic>.from(source) : const <String, dynamic>{};
    return AgentMention(
      id: json["id"] as String? ?? "",
      label: json["label"] as String? ?? "",
      path: sourceMap["path"] as String? ?? "",
      dataType: json["dataType"] as String? ?? "",
      value: json["value"],
    );
  }

  Map<String, dynamic> toJson() => {
        "id": id,
        "label": label,
        "source": {"kind": "asset", "path": path},
        "dataType": dataType,
        "value": value,
      };
}

/// 技能项。
class AgentSkill {
  final String name;
  final String displayName;
  final String description;

  const AgentSkill({
    required this.name,
    required this.displayName,
    required this.description,
  });

  factory AgentSkill.fromJson(Map<String, dynamic> json) => AgentSkill(
        name: json["name"] as String? ?? "",
        displayName: json["displayName"] as String? ?? "",
        description: json["description"] as String? ?? "",
      );
}

/// 资产列表项（提及资产选择用）。
class AgentAsset {
  final String path;
  final String name;
  final String type; // file / directory

  const AgentAsset({
    required this.path,
    required this.name,
    required this.type,
  });

  factory AgentAsset.fromJson(Map<String, dynamic> json) => AgentAsset(
        path: json["path"] as String? ?? "",
        name: json["name"] as String? ?? "",
        type: json["type"] as String? ?? "file",
      );

  bool get isDirectory => type == "directory";
}
