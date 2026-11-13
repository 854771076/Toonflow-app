import "dart:convert";

import "package:flutter/material.dart";
import "package:forui/forui.dart";

import "../../core/workspaceFiles.dart";
import "../../shared/appLocalizations.dart";
import "../../shared/designTokens.dart";
import "workspaceScan.dart";

class SearchHit {
  final String path;
  final int line;
  final String snippet;

  const SearchHit({
    required this.path,
    required this.line,
    required this.snippet,
  });
}

/// 工作区全文搜索：跳过二进制与画布文件，展示命中片段与行号。
class WorkspaceSearchDialog extends StatefulWidget {
  final WorkspaceFiles files;

  const WorkspaceSearchDialog({super.key, required this.files});

  @override
  State<WorkspaceSearchDialog> createState() => _WorkspaceSearchDialogState();
}

class _WorkspaceSearchDialogState extends State<WorkspaceSearchDialog> {
  final TextEditingController _controller = TextEditingController();
  List<SearchHit> _hits = const [];
  bool _searching = false;
  bool _searched = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _controller.text.trim();
    if (query.isEmpty) return;
    setState(() {
      _searching = true;
      _searched = true;
      _error = null;
      _hits = const [];
    });
    try {
      final files = await collectWorkspaceFiles(widget.files);
      final hits = <SearchHit>[];
      final lowered = query.toLowerCase();
      for (final entry in files) {
        if (isBinaryFile(entry.path)) continue;
        final text = await widget.files.readText(entry.path);
        if (entry.path.toLowerCase().endsWith(".json")) {
          Object? json;
          try {
            json = jsonDecode(text);
          } catch (_) {
            json = null;
          }
          if (isCanvasJson(json)) continue;
        }
        final lines = text.split("\n");
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          final index = line.toLowerCase().indexOf(lowered);
          if (index < 0) continue;
          hits.add(
            SearchHit(
              path: entry.path,
              line: i + 1,
              snippet: _snippet(line, index, query.length),
            ),
          );
        }
      }
      if (mounted) setState(() => _hits = hits);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  String _snippet(String line, int index, int length) {
    var start = index - 30;
    if (start < 0) start = 0;
    var end = index + length + 30;
    if (end > line.length) end = line.length;
    final prefix = start > 0 ? "…" : "";
    final suffix = end < line.length ? "…" : "";
    return "$prefix${line.substring(start, end)}$suffix";
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return FDialog(
      builder: (context, style) => Padding(
        padding: const EdgeInsets.all(DesignTokens.spaceXl),
        child: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.searchInWorkspace, style: style.titleTextStyle),
              const SizedBox(height: DesignTokens.spaceMd),
              SizedBox(
                height: 420,
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: FTextField(
                            control: FTextFieldControl.managed(controller: _controller),
                            autofocus: true,
                            hint: l10n.searchPlaceholder,
                            onSubmit: (_) => _search(),
                          ),
                        ),
                        const SizedBox(width: DesignTokens.spaceSm),
                        FButton.icon(
                          semanticsLabel: l10n.search,
                          onPress: _searching ? null : _search,
                          child: const Icon(FLucideIcons.search),
                        ),
                      ],
                    ),
                    const SizedBox(height: DesignTokens.spaceMd),
                    Expanded(child: _buildResults(l10n)),
                  ],
                ),
              ),
              const SizedBox(height: DesignTokens.spaceLg),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  FButton(
                    variant: .ghost,
                    mainAxisSize: .min,
                    onPress: () => Navigator.pop(context),
                    child: Text(l10n.cancel),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResults(AppLocalizations l10n) {
    if (_error != null) {
      return Center(child: Text(_error!));
    }
    if (_searching) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!_searched) {
      return const SizedBox.shrink();
    }
    if (_hits.isEmpty) {
      return Center(child: Text(l10n.noResults));
    }
    return ListView.builder(
      itemCount: _hits.length,
      itemBuilder: (context, index) {
        final hit = _hits[index];
        return FTile(
          prefix: const Icon(FLucideIcons.file),
          title: Text(hit.snippet, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            "${hit.path} : ${hit.line}",
            overflow: TextOverflow.ellipsis,
          ),
          onPress: () => Navigator.pop(context, hit.path),
        );
      },
    );
  }
}
