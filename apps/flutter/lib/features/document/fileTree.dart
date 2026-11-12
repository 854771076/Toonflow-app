import "package:flutter/material.dart";

import "../../core/workspaceFiles.dart";
import "../../shared/appLocalizations.dart";
import "workspaceScan.dart";

/// 工作区文件树：目录惰性展开，点击文件通过 [onOpenFile] 打开。
class FileTree extends StatefulWidget {
  final WorkspaceFiles files;
  final ValueChanged<String> onOpenFile;

  const FileTree({super.key, required this.files, required this.onOpenFile});

  @override
  State<FileTree> createState() => _FileTreeState();
}

class _FileTreeState extends State<FileTree> {
  List<WorkspaceEntry>? _roots;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRoots();
  }

  Future<void> _loadRoots() async {
    try {
      final result = await widget.files.list("");
      final entries = (result["entries"] as List? ?? const [])
          .map(
            (entry) =>
                WorkspaceEntry.fromJson(Map<String, dynamic>.from(entry as Map)),
          )
          .toList();
      if (mounted) setState(() => _roots = entries);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(_error!),
        ),
      );
    }
    final roots = _roots;
    if (roots == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (roots.isEmpty) {
      return Center(child: Text(l10n.noFiles));
    }
    return ListView(
      children: [
        for (final entry in roots)
          _FileTreeTile(
            files: widget.files,
            entry: entry,
            depth: 0,
            onOpenFile: widget.onOpenFile,
          ),
      ],
    );
  }
}

class _FileTreeTile extends StatefulWidget {
  final WorkspaceFiles files;
  final WorkspaceEntry entry;
  final int depth;
  final ValueChanged<String> onOpenFile;

  const _FileTreeTile({
    required this.files,
    required this.entry,
    required this.depth,
    required this.onOpenFile,
  });

  @override
  State<_FileTreeTile> createState() => _FileTreeTileState();
}

class _FileTreeTileState extends State<_FileTreeTile> {
  List<WorkspaceEntry>? _children;
  bool _loading = false;

  Future<void> _loadChildren() async {
    if (_children != null || _loading) return;
    setState(() => _loading = true);
    try {
      final result = await widget.files.list(widget.entry.path);
      final children = (result["entries"] as List? ?? const [])
          .map(
            (entry) =>
                WorkspaceEntry.fromJson(Map<String, dynamic>.from(entry as Map)),
          )
          .toList();
      if (mounted) setState(() => _children = children);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final indent = 12.0 + widget.depth * 16.0;
    if (!widget.entry.isDirectory) {
      return ListTile(
        contentPadding: EdgeInsets.only(left: indent),
        dense: true,
        visualDensity: VisualDensity.compact,
        leading: const Icon(Icons.description_outlined, size: 18),
        title: Text(widget.entry.name, overflow: TextOverflow.ellipsis),
        onTap: () => widget.onOpenFile(widget.entry.path),
      );
    }
    return ExpansionTile(
      tilePadding: EdgeInsets.only(left: indent),
      dense: true,
      visualDensity: VisualDensity.compact,
      leading: const Icon(Icons.folder_outlined, size: 18),
      title: Text(widget.entry.name, overflow: TextOverflow.ellipsis),
      trailing: _loading
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : null,
      onExpansionChanged: (expanded) {
        if (expanded) _loadChildren();
      },
      children: _children == null
          ? const []
          : [
              for (final child in _children!)
                _FileTreeTile(
                  files: widget.files,
                  entry: child,
                  depth: widget.depth + 1,
                  onOpenFile: widget.onOpenFile,
                ),
            ],
    );
  }
}
