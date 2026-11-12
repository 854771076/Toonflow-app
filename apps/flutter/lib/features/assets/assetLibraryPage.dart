import "dart:typed_data";

import "package:flutter/material.dart";

import "../../core/apiClient.dart";
import "../../shared/appLocalizations.dart";

/// 根据文件扩展名推断 mimeType；无法识别时返回 null。
String? assetMimeType(String path) {
  final lower = path.toLowerCase();
  if (lower.endsWith(".png")) return "image/png";
  if (lower.endsWith(".jpg") || lower.endsWith(".jpeg")) return "image/jpeg";
  if (lower.endsWith(".webp")) return "image/webp";
  if (lower.endsWith(".gif")) return "image/gif";
  if (lower.endsWith(".bmp")) return "image/bmp";
  if (lower.endsWith(".mp4")) return "video/mp4";
  if (lower.endsWith(".webm")) return "video/webm";
  if (lower.endsWith(".mov")) return "video/quicktime";
  if (lower.endsWith(".mp3")) return "audio/mpeg";
  if (lower.endsWith(".wav")) return "audio/wav";
  if (lower.endsWith(".ogg")) return "audio/ogg";
  if (lower.endsWith(".m4a")) return "audio/mp4";
  if (lower.endsWith(".aac")) return "audio/aac";
  if (lower.endsWith(".flac")) return "audio/flac";
  return null;
}

/// 按 mimeType 前缀推断媒体类型；无法识别（含 `audio/pcm`）返回 null。
String? assetMediaKind(String path) {
  final mime = assetMimeType(path);
  if (mime == null) return null;
  if (mime.startsWith("image/")) return "image";
  if (mime.startsWith("video/")) return "video";
  if (mime.startsWith("audio/")) return "audio";
  return null;
}

/// 中文自然排序：数字段按数值比较，其余按码点。
/// ACT: 中文按 Unicode 码点近似排序（非拼音），避免引入 intl 依赖；
/// 与 web 端 `localeCompare(zh-CN)` 在个别多音字上可能略有差异。
int _naturalCompare(String a, String b) {
  final re = RegExp(r"\d+|\D+");
  final aParts = re.allMatches(a).map((m) => m.group(0)!).toList();
  final bParts = re.allMatches(b).map((m) => m.group(0)!).toList();
  final len = aParts.length < bParts.length ? aParts.length : bParts.length;
  for (int i = 0; i < len; i++) {
    final aNum = int.tryParse(aParts[i]);
    final bNum = int.tryParse(bParts[i]);
    final cmp = aNum != null && bNum != null
        ? aNum.compareTo(bNum)
        : aParts[i].compareTo(bParts[i]);
    if (cmp != 0) return cmp;
  }
  return aParts.length.compareTo(bParts.length);
}

class _AssetEntry {
  final String name;
  final String path;
  final String type;
  final List<_AssetEntry> children;

  const _AssetEntry({
    required this.name,
    required this.path,
    required this.type,
    this.children = const [],
  });

  factory _AssetEntry.fromJson(Map<String, dynamic> json) => _AssetEntry(
        name: json["name"] as String? ?? "",
        path: json["path"] as String? ?? "",
        type: json["type"] as String? ?? "file",
        children: (json["children"] as List? ?? const [])
            .map((e) => _AssetEntry.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );
}

/// 素材库（全局资产库）页面。
///
/// 浏览模式（[selecting] 为 false）仅展示素材；选择模式下点选与 [mediaKind]
/// 匹配的文件后，以相对路径字符串 `pop` 返回，供画布节点引用。
class AssetLibraryPage extends StatefulWidget {
  final ApiClient client;
  final bool selecting;
  final String? mediaKind;

  const AssetLibraryPage({
    super.key,
    required this.client,
    this.selecting = false,
    this.mediaKind,
  });

  @override
  State<AssetLibraryPage> createState() => _AssetLibraryPageState();
}

class _AssetLibraryPageState extends State<AssetLibraryPage> {
  List<_AssetEntry> _entries = [];
  bool _loading = true;
  String? _error;

  String _folder = ".";
  String _search = "";
  String _kind = "all";

  final Map<String, Uint8List> _imageCache = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.client.getData("/api/assets/list") as Map<String, dynamic>;
      final entries = (data["entries"] as List? ?? const [])
          .map((e) => _AssetEntry.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  List<_AssetEntry> _collectFiles(List<_AssetEntry> entries) {
    final result = <_AssetEntry>[];
    for (final entry in entries) {
      if (entry.type == "file") {
        result.add(entry);
      } else {
        result.addAll(_collectFiles(entry.children));
      }
    }
    return result;
  }

  _AssetEntry? _findDirectory(String path) {
    _AssetEntry? walk(List<_AssetEntry> list) {
      for (final entry in list) {
        if (entry.type == "directory" && entry.path == path) return entry;
        final found = walk(entry.children);
        if (found != null) return found;
      }
      return null;
    }

    return walk(_entries);
  }

  List<_AssetEntry> get _scopeEntries {
    if (_folder == ".") return _collectFiles(_entries);
    return _findDirectory(_folder)?.children ?? const [];
  }

  List<_AssetEntry> get _displayEntries {
    final query = _search.trim().toLowerCase();
    final list = _scopeEntries.where((entry) {
      if (query.isNotEmpty && !entry.name.toLowerCase().contains(query)) {
        return false;
      }
      if (_kind == "all") return true;
      if (entry.type != "file") return false;
      return (assetMediaKind(entry.path) ?? "other") == _kind;
    }).toList();
    list.sort((a, b) {
      final dirDiff =
          (a.type == "directory" ? 0 : 1) - (b.type == "directory" ? 0 : 1);
      if (dirDiff != 0) return dirDiff;
      return _naturalCompare(a.name, b.name);
    });
    return list;
  }

  void _navigateTo(String path) {
    setState(() {
      _folder = path;
      _kind = "all";
    });
  }

  void _openEntry(_AssetEntry entry) {
    if (entry.type == "directory") {
      _navigateTo(entry.path);
      return;
    }
    if (!widget.selecting) return;
    if (widget.mediaKind == null ||
        assetMediaKind(entry.path) == widget.mediaKind) {
      Navigator.of(context).pop(entry.path);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.selecting ? l10n.chooseAsset : l10n.assetLibrary),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(_error!),
                      const SizedBox(height: 8),
                      OutlinedButton(
                        onPressed: _load,
                        child: Text(l10n.retry),
                      ),
                    ],
                  ),
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 200,
                      child: _buildSidebar(l10n),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(child: _buildMain(l10n)),
                  ],
                ),
    );
  }

  Widget _buildSidebar(AppLocalizations l10n) {
    final dirs = _entries.where((e) => e.type == "directory").toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: ListTile(
            dense: true,
            selected: _folder == ".",
            selectedTileColor: Theme.of(context).colorScheme.primaryContainer,
            leading: const Icon(Icons.grid_view_outlined),
            title: Text(l10n.allAssets),
            onTap: () => _navigateTo("."),
          ),
        ),
        Expanded(
          child: ListView(
            children: dirs
                .map((dir) => _DirectoryTile(
                      entry: dir,
                      folder: _folder,
                      onSelect: _navigateTo,
                    ))
                .toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildMain(AppLocalizations l10n) {
    final entries = _displayEntries;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            decoration: InputDecoration(
              hintText: l10n.searchAssets,
              prefixIcon: const Icon(Icons.search),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (value) => setState(() => _search = value),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8,
            children: [
              _kindChip("all", l10n.all),
              _kindChip("image", l10n.image),
              _kindChip("video", l10n.video),
              _kindChip("audio", l10n.audio),
              _kindChip("other", l10n.other),
            ],
          ),
        ),
        Expanded(
          child: entries.isEmpty
              ? Center(child: Text(l10n.noAssets))
              : Padding(
                  padding: const EdgeInsets.all(16),
                  child: GridView.builder(
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 220,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 1.05,
                    ),
                    itemCount: entries.length,
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      final isFile = entry.type == "file";
                      final enabled = isFile
                          ? widget.mediaKind == null ||
                              assetMediaKind(entry.path) == widget.mediaKind
                          : true;
                      return _AssetCard(
                        client: widget.client,
                        entry: entry,
                        imageCache: _imageCache,
                        enabled: enabled,
                        onTap: enabled ? () => _openEntry(entry) : null,
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _kindChip(String value, String label) {
    return ChoiceChip(
      label: Text(label),
      selected: _kind == value,
      onSelected: (_) => setState(() => _kind = value),
    );
  }
}

class _DirectoryTile extends StatefulWidget {
  final _AssetEntry entry;
  final String folder;
  final ValueChanged<String> onSelect;

  const _DirectoryTile({
    required this.entry,
    required this.folder,
    required this.onSelect,
  });

  @override
  State<_DirectoryTile> createState() => _DirectoryTileState();
}

class _DirectoryTileState extends State<_DirectoryTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final dirs = widget.entry.children
        .where((e) => e.type == "directory")
        .toList();
    final selected = widget.folder == widget.entry.path;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => widget.onSelect(widget.entry.path),
          child: Container(
            color: selected
                ? Theme.of(context).colorScheme.primaryContainer
                : null,
            padding: const EdgeInsets.only(left: 4, right: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 32,
                  height: 32,
                  child: dirs.isEmpty
                      ? null
                      : InkWell(
                          onTap: () => setState(() => _expanded = !_expanded),
                          child: Icon(
                            _expanded
                                ? Icons.expand_more
                                : Icons.chevron_right,
                            size: 18,
                          ),
                        ),
                ),
                const Icon(Icons.folder_outlined, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.entry.name,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_expanded && dirs.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: dirs
                  .map((dir) => _DirectoryTile(
                        entry: dir,
                        folder: widget.folder,
                        onSelect: widget.onSelect,
                      ))
                  .toList(),
            ),
          ),
      ],
    );
  }
}

class _AssetCard extends StatefulWidget {
  final ApiClient client;
  final _AssetEntry entry;
  final Map<String, Uint8List> imageCache;
  final bool enabled;
  final VoidCallback? onTap;

  const _AssetCard({
    required this.client,
    required this.entry,
    required this.imageCache,
    required this.enabled,
    required this.onTap,
  });

  @override
  State<_AssetCard> createState() => _AssetCardState();
}

class _AssetCardState extends State<_AssetCard> {
  Uint8List? _bytes;
  bool _failed = false;

  bool get _isImage =>
      widget.entry.type == "file" &&
      assetMediaKind(widget.entry.path) == "image";

  @override
  void initState() {
    super.initState();
    if (_isImage) {
      final cached = widget.imageCache[widget.entry.path];
      if (cached != null) {
        _bytes = cached;
      } else {
        _loadImage();
      }
    }
  }

  Future<void> _loadImage() async {
    try {
      final bytes = await widget.client
          .getBytes("/api/assets/read", query: {"path": widget.entry.path});
      widget.imageCache[widget.entry.path] = bytes;
      if (!mounted) return;
      setState(() => _bytes = bytes);
    } catch (_) {
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final kind = assetMediaKind(widget.entry.path);
    return InkWell(
      onTap: widget.onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(8),
        ),
        clipBehavior: Clip.antiAlias,
        child: Opacity(
          opacity: widget.enabled ? 1 : 0.4,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _buildVisual(kind)),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                child: Text(
                  widget.entry.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVisual(String? kind) {
    final colorScheme = Theme.of(context).colorScheme;
    final placeholder = colorScheme.onSurfaceVariant;
    if (widget.entry.type == "directory") {
      return Icon(Icons.folder, size: 52, color: colorScheme.secondary);
    }
    if (_isImage) {
      if (_bytes != null) {
        return Image.memory(
          _bytes!,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
        );
      }
      if (_failed) {
        return Icon(Icons.broken_image_outlined, size: 52, color: placeholder);
      }
      return const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    final IconData icon;
    switch (kind) {
      case "video":
        icon = Icons.movie_outlined;
        break;
      case "audio":
        icon = Icons.audiotrack;
        break;
      default:
        icon = Icons.insert_drive_file_outlined;
    }
    return Icon(icon, size: 52, color: placeholder);
  }
}
