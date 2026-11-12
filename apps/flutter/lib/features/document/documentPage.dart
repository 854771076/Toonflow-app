import "package:flutter/material.dart";

import "../../core/apiClient.dart";
import "../../core/workspaceFiles.dart";
import "../../shared/appLocalizations.dart";
import "fileTree.dart";
import "quickOpenDialog.dart";
import "textEditor.dart";
import "workspaceSearchDialog.dart";

/// 文档编辑页：左侧文件树 + 右侧多标签文本编辑器。
class DocumentPage extends StatefulWidget {
  final ApiClient client;
  final String directory;
  final String title;

  const DocumentPage({
    super.key,
    required this.client,
    required this.directory,
    required this.title,
  });

  @override
  State<DocumentPage> createState() => _DocumentPageState();
}

class _OpenedFile {
  _OpenedFile({required this.path, required this.content});

  final String path;
  String content;
  bool dirty = false;

  String get name {
    final segments = path.split("/");
    return segments.isEmpty ? path : segments.last;
  }
}

class _DocumentPageState extends State<DocumentPage> {
  late final WorkspaceFiles _files;
  final List<_OpenedFile> _tabs = [];
  int _activeIndex = -1;

  @override
  void initState() {
    super.initState();
    _files = WorkspaceFiles(
      client: widget.client,
      directory: widget.directory,
    );
  }

  Future<void> _openFile(String path) async {
    final existing = _tabs.indexWhere((tab) => tab.path == path);
    if (existing >= 0) {
      setState(() => _activeIndex = existing);
      return;
    }
    try {
      final content = await _files.readText(path);
      if (!mounted) return;
      setState(() {
        _tabs.add(_OpenedFile(path: path, content: content));
        _activeIndex = _tabs.length - 1;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }

  Future<void> _saveTab(int index) async {
    final tab = _tabs[index];
    try {
      await _files.writeText(tab.path, tab.content);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
      return;
    }
    if (!mounted) return;
    setState(() => tab.dirty = false);
  }

  Future<void> _closeTab(int index) async {
    final tab = _tabs[index];
    if (tab.dirty && !await _confirmDiscard(tab.name)) return;
    if (!mounted) return;
    setState(() {
      _tabs.removeAt(index);
      if (_activeIndex >= _tabs.length) _activeIndex = _tabs.length - 1;
    });
  }

  Future<void> _closeAll() async {
    if (_tabs.any((tab) => tab.dirty)) {
      final l10n = AppLocalizations.of(context);
      if (!await _confirmDiscard(l10n.unsaved)) return;
    }
    if (!mounted) return;
    setState(() {
      _tabs.clear();
      _activeIndex = -1;
    });
  }

  Future<bool> _confirmDiscard(String label) async {
    final l10n = AppLocalizations.of(context);
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text("${l10n.unsaved}: $label"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.closeTab),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<void> _newFile() async {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.newFile),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: l10n.fileName,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(l10n.confirm),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;
    try {
      await _files.writeText(name, "", exclusive: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      _tabs.add(_OpenedFile(path: name, content: ""));
      _activeIndex = _tabs.length - 1;
    });
  }

  Future<void> _quickOpen() async {
    final path = await showDialog<String>(
      context: context,
      builder: (_) => QuickOpenDialog(files: _files),
    );
    if (path != null && mounted) _openFile(path);
  }

  Future<void> _search() async {
    final path = await showDialog<String>(
      context: context,
      builder: (_) => WorkspaceSearchDialog(files: _files),
    );
    if (path != null && mounted) _openFile(path);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.note_add_outlined),
            tooltip: l10n.newFile,
            onPressed: _newFile,
          ),
          IconButton(
            icon: const Icon(Icons.file_open_outlined),
            tooltip: l10n.quickOpen,
            onPressed: _quickOpen,
          ),
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: l10n.searchInWorkspace,
            onPressed: _search,
          ),
        ],
      ),
      body: Row(
        children: [
          SizedBox(
            width: 220,
            child: FileTree(files: _files, onOpenFile: _openFile),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: _buildEditorArea(l10n)),
        ],
      ),
    );
  }

  Widget _buildEditorArea(AppLocalizations l10n) {
    if (_tabs.isEmpty) {
      return Center(child: Text(l10n.noOpenFiles));
    }
    final tab = _tabs[_activeIndex];
    return Column(
      children: [
        _buildTabBar(l10n),
        const Divider(height: 1),
        Expanded(
          child: TextEditor(
            key: ValueKey(tab.path),
            initialText: tab.content,
            onChanged: (text) {
              tab.content = text;
              tab.dirty = true;
              setState(() {});
            },
            onSave: () => _saveTab(_activeIndex),
          ),
        ),
      ],
    );
  }

  Widget _buildTabBar(AppLocalizations l10n) {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (var i = 0; i < _tabs.length; i++) _buildTab(i, l10n),
          IconButton(
            icon: const Icon(Icons.close, size: 16),
            tooltip: l10n.closeAll,
            onPressed: _tabs.isEmpty ? null : _closeAll,
          ),
        ],
      ),
    );
  }

  Widget _buildTab(int index, AppLocalizations l10n) {
    final tab = _tabs[index];
    final active = index == _activeIndex;
    return InkWell(
      onTap: () => setState(() => _activeIndex = index),
      child: Container(
        padding: const EdgeInsets.only(left: 12, right: 2),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: active
                  ? Theme.of(context).colorScheme.primary
                  : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              tab.dirty ? "${tab.name} •" : tab.name,
              overflow: TextOverflow.ellipsis,
            ),
            InkWell(
              onTap: () => _closeTab(index),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(
                  Icons.close,
                  size: 14,
                  semanticLabel: l10n.closeTab,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
