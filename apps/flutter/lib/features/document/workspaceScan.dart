import "../../core/config.dart";
import "../../core/workspaceFiles.dart";

/// 工作区文件条目，对应服务端 list 返回的每一项。
class WorkspaceEntry {
  final String name;
  final String path;
  final String type;

  const WorkspaceEntry({
    required this.name,
    required this.path,
    required this.type,
  });

  bool get isDirectory => type == "directory";

  static WorkspaceEntry fromJson(Map<String, dynamic> json) => WorkspaceEntry(
    name: json["name"] as String? ?? "",
    path: json["path"] as String? ?? "",
    type: json["type"] as String? ?? "file",
  );
}

/// 无法直接编辑的二进制扩展名，全文搜索时跳过。
final RegExp _binaryExtensions = RegExp(
  r"\.(png|jpe?g|webp|gif|bmp|avif|ico|tiff?|pdf|mp[34]|wav|flac|ogg|m4[av]|webm|mov|avi|mkv|zip|rar|7z|gz|tar|exe|dll|bin|wasm|woff2?|ttf|otf|sqlite|db|docx?|xlsx?|pptx?|psd)$",
  caseSensitive: false,
);

/// 是否属于二进制素材文件，不适合文本搜索。
bool isBinaryFile(String path) => _binaryExtensions.hasMatch(path);

/// 是否为画布 JSON 文档（全文搜索时跳过画布文件）。
bool isCanvasJson(Object? json) {
  if (json is! Map) return false;
  return json[ServerFields.canvasMark] == true;
}

/// 广度优先收集工作区内全部文件（不含目录）。
Future<List<WorkspaceEntry>> collectWorkspaceFiles(WorkspaceFiles files) async {
  final filesFound = <WorkspaceEntry>[];
  final pending = <String>[""];
  for (var index = 0; index < pending.length; index++) {
    final result = await files.list(pending[index]);
    final entries = (result["entries"] as List? ?? const [])
        .map(
          (entry) =>
              WorkspaceEntry.fromJson(Map<String, dynamic>.from(entry as Map)),
        )
        .toList();
    for (final entry in entries) {
      if (entry.isDirectory) {
        pending.add(entry.path);
      } else {
        filesFound.add(entry);
      }
    }
  }
  return filesFound;
}
