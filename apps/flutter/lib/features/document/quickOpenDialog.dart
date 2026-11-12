import "package:flutter/material.dart";

import "../../core/workspaceFiles.dart";
import "../../shared/appLocalizations.dart";
import "workspaceScan.dart";

/// 快速打开：输入文件名模糊匹配工作区文件，点击打开。
class QuickOpenDialog extends StatefulWidget {
  final WorkspaceFiles files;

  const QuickOpenDialog({super.key, required this.files});

  @override
  State<QuickOpenDialog> createState() => _QuickOpenDialogState();
}

class _QuickOpenDialogState extends State<QuickOpenDialog> {
  List<WorkspaceEntry>? _allFiles;
  String? _error;
  String _query = "";

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _allFiles = null;
      _error = null;
    });
    try {
      final files = await collectWorkspaceFiles(widget.files);
      if (mounted) setState(() => _allFiles = files);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  List<WorkspaceEntry> get _results {
    final all = _allFiles ?? const <WorkspaceEntry>[];
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return all;
    final matches = all
        .where(
          (entry) =>
              entry.name.toLowerCase().contains(query) ||
              entry.path.toLowerCase().contains(query),
        )
        .toList()
      ..sort((left, right) {
        final leftStart = left.name.toLowerCase().startsWith(query) ? 1 : 0;
        final rightStart = right.name.toLowerCase().startsWith(query) ? 1 : 0;
        return rightStart - leftStart;
      });
    return matches.length > 100 ? matches.sublist(0, 100) : matches;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.quickOpen),
      content: SizedBox(
        width: 480,
        height: 400,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: InputDecoration(
                hintText: l10n.fileName,
                border: const OutlineInputBorder(),
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
            const SizedBox(height: 12),
            Expanded(child: _buildList(l10n)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
      ],
    );
  }

  Widget _buildList(AppLocalizations l10n) {
    if (_error != null) {
      return Center(child: Text(_error!));
    }
    if (_allFiles == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final results = _results;
    if (results.isEmpty) {
      return Center(child: Text(l10n.noResults));
    }
    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (context, index) {
        final entry = results[index];
        return ListTile(
          dense: true,
          leading: const Icon(Icons.description_outlined),
          title: Text(entry.name, overflow: TextOverflow.ellipsis),
          subtitle: Text(entry.path, overflow: TextOverflow.ellipsis),
          onTap: () => Navigator.pop(context, entry.path),
        );
      },
    );
  }
}
