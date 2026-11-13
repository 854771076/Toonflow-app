import "package:flutter/material.dart";
import "package:forui/forui.dart";

import "../../shared/appLocalizations.dart";
import "agentApi.dart";
import "agentTypes.dart";

/// 资产提及弹窗：浏览工作区资产目录，选中文件后回传 [AgentMention]。
class AgentMentionSheet extends StatefulWidget {
  final AgentApi api;

  const AgentMentionSheet({super.key, required this.api});

  @override
  State<AgentMentionSheet> createState() => _AgentMentionSheetState();
}

class _AgentMentionSheetState extends State<AgentMentionSheet> {
  final List<String> _pathStack = [];
  List<AgentAsset> _assets = [];
  bool _loading = true;
  String? _error;

  String get _currentPath => _pathStack.isEmpty ? "" : _pathStack.last;

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
      final assets = await widget.api.listAssets(path: _currentPath);
      if (!mounted) return;
      setState(() {
        _assets = assets;
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

  Future<void> _openDirectory(AgentAsset asset) async {
    setState(() => _pathStack.add(asset.path));
    await _load();
  }

  Future<void> _goBack() async {
    setState(() => _pathStack.removeLast());
    await _load();
  }

  Future<void> _selectAsset(AgentAsset asset) async {
    try {
      final mention = await widget.api.selectAsset(asset.path);
      if (!mounted) return;
      Navigator.pop(context, mention);
    } catch (e) {
      if (!mounted) return;
      showFToast(
        context: context,
        variant: .destructive,
        title: Text(e.toString()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(l10n.mention, style: context.theme.typography.display.lg),
                  ),
                  if (_pathStack.isNotEmpty)
                    FButton.icon(
                      onPress: _goBack,
                      variant: .ghost,
                      semanticsTooltip: l10n.back,
                      child: const Icon(FLucideIcons.arrowLeft),
                    ),
                ],
              ),
            ),
            FDivider(style: .delta(padding: .value(EdgeInsets.zero))),
            Expanded(child: _buildBody(l10n)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(AppLocalizations l10n) {
    if (_loading) {
      return const Center(child: FCircularProgress());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!),
            const SizedBox(height: 8),
            FButton(
              onPress: _load,
              variant: .outline,
              child: Text(l10n.retry),
            ),
          ],
        ),
      );
    }
    if (_assets.isEmpty) {
      return Center(
        child: Text(
          l10n.noFiles,
          style: TextStyle(color: context.theme.colors.muted),
        ),
      );
    }
    return ListView.builder(
      itemCount: _assets.length,
      itemBuilder: (context, index) {
        final asset = _assets[index];
        return FTile(
          prefix: Icon(
            asset.isDirectory ? FLucideIcons.folder : FLucideIcons.file,
          ),
          title: Text(asset.name),
          onPress: asset.isDirectory
              ? () => _openDirectory(asset)
              : () => _selectAsset(asset),
        );
      },
    );
  }
}
