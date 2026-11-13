import "../../core/config.dart";

/// 9 种画布节点类型（服务端契约，type 带 remote- 前缀，原样保存）。
/// [canvasGroup] 为本地分组容器类型，不参与“添加节点”面板，仅由打组创建。
class CanvasNodeType {
  CanvasNodeType._();

  static const String text = "remote-textNode";
  static const String image = "remote-imageNode";
  static const String video = "remote-videoNode";
  static const String audio = "remote-audioNode";
  static const String imageGeneration = "remote-imageGenerationNode";
  static const String videoGeneration = "remote-videoGenerationNode";
  static const String audioGeneration = "remote-audioGenerationNode";
  static const String director3d = "remote-director3dNode";
  static const String frameAnalysis = "remote-frameAnalysisNode";
  static const String canvasGroup = "canvasGroup";

  static const List<String> all = [
    text,
    image,
    video,
    audio,
    imageGeneration,
    videoGeneration,
    audioGeneration,
    director3d,
    frameAnalysis,
  ];

  /// 生成类节点，数据中有 prompt 字段。
  static const Set<String> generation = {
    imageGeneration,
    videoGeneration,
    audioGeneration,
  };
}

class CanvasNode {
  final String id;
  final String type;
  final double x;
  final double y;
  final Map<String, dynamic> data;
  final bool selected;

  /// 子节点指向所属分组的 id；分组容器自身为 null（不嵌套分组）。
  final String? parentNode;

  /// 分组容器的宽高（世界坐标），仅 [CanvasNodeType.canvasGroup] 使用。
  final double? width;
  final double? height;

  static const Object _unset = Object();

  CanvasNode({
    required this.id,
    required this.type,
    required this.x,
    required this.y,
    required this.data,
    this.selected = false,
    this.parentNode,
    this.width,
    this.height,
  });

  String get label => data["label"]?.toString() ?? "";

  String get prompt => data["prompt"]?.toString() ?? "";

  bool get isGroup => type == CanvasNodeType.canvasGroup;

  String get groupColor => data["groupColor"]?.toString() ?? "#808080";

  double get groupOpacity {
    final value = data["groupOpacity"];
    return value is num ? value.toDouble() : 25;
  }

  CanvasNode copyWith({
    double? x,
    double? y,
    Map<String, dynamic>? data,
    bool? selected,
    Object? parentNode = _unset,
    double? width,
    double? height,
  }) {
    return CanvasNode(
      id: id,
      type: type,
      x: x ?? this.x,
      y: y ?? this.y,
      data: data ?? this.data,
      selected: selected ?? this.selected,
      parentNode: identical(parentNode, _unset)
          ? this.parentNode
          : parentNode as String?,
      width: width ?? this.width,
      height: height ?? this.height,
    );
  }

  Map<String, dynamic> toJson() => {
    "id": id,
    "type": type,
    "position": {"x": x, "y": y},
    "data": data,
    "selected": selected,
    if (parentNode != null) "parentNode": parentNode,
    if (width != null) "width": width,
    if (height != null) "height": height,
  };

  static CanvasNode fromJson(Map<String, dynamic> json) {
    final position = json["position"];
    double x = 0;
    double y = 0;
    if (position is Map) {
      x = (position["x"] as num?)?.toDouble() ?? 0;
      y = (position["y"] as num?)?.toDouble() ?? 0;
    }
    return CanvasNode(
      id: json["id"] as String? ?? "",
      type: json["type"] as String? ?? "",
      x: x,
      y: y,
      data: json["data"] is Map
          ? Map<String, dynamic>.from(json["data"] as Map)
          : <String, dynamic>{},
      selected: json["selected"] == true,
      parentNode: json["parentNode"] as String?,
      width: (json["width"] as num?)?.toDouble(),
      height: (json["height"] as num?)?.toDouble(),
    );
  }
}

class CanvasEdge {
  final String id;
  final String source;
  final String target;
  final String? sourceHandle;
  final String? targetHandle;

  CanvasEdge({
    required this.id,
    required this.source,
    required this.target,
    this.sourceHandle,
    this.targetHandle,
  });

  Map<String, dynamic> toJson() => {
    "id": id,
    "source": source,
    "target": target,
    "sourceHandle": sourceHandle,
    "targetHandle": targetHandle,
  };

  static CanvasEdge fromJson(Map<String, dynamic> json) => CanvasEdge(
    id: json["id"] as String? ?? "",
    source: json["source"] as String? ?? "",
    target: json["target"] as String? ?? "",
    sourceHandle: json["sourceHandle"] as String?,
    targetHandle: json["targetHandle"] as String?,
  );
}

class CanvasViewport {
  final double x;
  final double y;
  final double zoom;

  const CanvasViewport({this.x = 0, this.y = 0, this.zoom = 1});

  CanvasViewport copyWith({double? x, double? y, double? zoom}) => CanvasViewport(
    x: x ?? this.x,
    y: y ?? this.y,
    zoom: zoom ?? this.zoom,
  );

  Map<String, dynamic> toJson() => {"x": x, "y": y, "zoom": zoom};

  static CanvasViewport fromJson(Map<String, dynamic> json) {
    final zoom = (json["zoom"] as num?)?.toDouble() ?? 1;
    return CanvasViewport(
      x: (json["x"] as num?)?.toDouble() ?? 0,
      y: (json["y"] as num?)?.toDouble() ?? 0,
      zoom: zoom > 0 ? zoom : 1,
    );
  }
}

class CanvasDocument {
  List<CanvasNode> nodes;
  List<CanvasEdge> edges;
  CanvasViewport viewport;

  CanvasDocument({
    required this.nodes,
    required this.edges,
    required this.viewport,
  });

  factory CanvasDocument.empty() => CanvasDocument(
    nodes: [],
    edges: [],
    viewport: const CanvasViewport(),
  );

  Map<String, dynamic> toJson() => {
    ServerFields.canvasMark: true,
    "nodes": nodes.map((n) => n.toJson()).toList(),
    "edges": edges.map((e) => e.toJson()).toList(),
    "viewport": viewport.toJson(),
  };

  static CanvasDocument fromJson(Map<String, dynamic> json) => CanvasDocument(
    nodes: (json["nodes"] as List? ?? const [])
        .map((e) => CanvasNode.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList(),
    edges: (json["edges"] as List? ?? const [])
        .map((e) => CanvasEdge.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList(),
    viewport: json["viewport"] is Map
        ? CanvasViewport.fromJson(
            Map<String, dynamic>.from(json["viewport"] as Map),
          )
        : const CanvasViewport(),
  );

  /// 是否为画布文档（根对象首字段为画布标记）。
  static bool isCanvas(Map<String, dynamic> json) =>
      json[ServerFields.canvasMark] == true;
}
