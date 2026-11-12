import "dart:async";
import "dart:convert";
import "dart:math";

import "package:flutter/material.dart";

import "../../core/apiClient.dart";
import "../../core/workspaceFiles.dart";
import "../../shared/appLocalizations.dart";
import "../agent/agentPage.dart";
import "../assets/assetLibraryPage.dart";
import "../document/documentPage.dart";
import "canvasModel.dart";
import "canvasPainter.dart";

enum _GestureMode { none, pan, scale, nodeDrag, connect }

/// 无限画布编辑页：自绘节点/连线，支持平移、缩放、框选、连线与持久化。
class CanvasPage extends StatefulWidget {
  final ApiClient client;
  final String directory;
  final String title;

  const CanvasPage({
    super.key,
    required this.client,
    required this.directory,
    required this.title,
  });

  @override
  State<CanvasPage> createState() => _CanvasPageState();
}

class _CanvasPageState extends State<CanvasPage> {
  final Random _rng = Random();

  WorkspaceFiles? _files;
  CanvasDocument _doc = CanvasDocument.empty();
  String _canvasPath = "";
  bool _loading = true;
  String? _loadError;
  bool _snapEnabled = true;
  Size _canvasSize = Size.zero;

  _GestureMode _mode = _GestureMode.none;
  String? _dragNodeId;
  double _dragNodeStartX = 0;
  double _dragNodeStartY = 0;
  Offset _gestureStartFocal = Offset.zero;
  CanvasViewport _gestureStartViewport = const CanvasViewport();
  bool _gestureMoved = false;
  CanvasConnectionDraft? _connection;
  Offset? _selectionStart;
  Rect? _selectionRect;

  String? _editingNodeId;
  Timer? _saveTimer;

  bool get _hasSelection => _doc.nodes.any((n) => n.selected);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final files = WorkspaceFiles(
        client: widget.client,
        directory: widget.directory,
      );
      final root = await files.list("");
      final entries = (root["entries"] as List? ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      String? canvasPath;
      CanvasDocument doc = CanvasDocument.empty();
      for (final entry in entries) {
        if (entry["type"] != "file") continue;
        final name = entry["name"] as String? ?? "";
        if (!name.toLowerCase().endsWith(".json")) continue;
        final path = entry["path"] as String? ?? name;
        try {
          final json = await files.readJson(path);
          if (json is Map<String, dynamic> && CanvasDocument.isCanvas(json)) {
            canvasPath = path;
            doc = CanvasDocument.fromJson(json);
            break;
          }
        } catch (_) {
          // 非画布 JSON 或读取失败的文件跳过，继续查找画布。
        }
      }

      final isNew = canvasPath == null;
      final resolvedPath = canvasPath ?? _nextCanvasPath(entries);
      if (isNew) {
        await files.writeText(resolvedPath, jsonEncode(doc.toJson()));
      }

      if (!mounted) return;
      setState(() {
        _files = files;
        _canvasPath = resolvedPath;
        _doc = doc;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.toString();
        _loading = false;
      });
    }
  }

  String _nextCanvasPath(List<Map<String, dynamic>> entries) {
    final names = entries.map((e) => e["name"] as String? ?? "").toSet();
    for (int i = 1; ; i++) {
      final name = "画布$i.json";
      if (!names.contains(name)) return name;
    }
  }

  String _newId(String prefix) {
    final bytes = List<int>.generate(16, (_) => _rng.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, "0")).join();
    return "$prefix-$hex";
  }

  double _snap(double value) =>
      (value / canvasSnapStep).roundToDouble() * canvasSnapStep;

  CanvasNode? _hitNode(Offset screen) {
    for (final node in _doc.nodes.reversed) {
      if (canvasNodeScreenRect(node, _doc.viewport).contains(screen)) {
        return node;
      }
    }
    return null;
  }

  String? _hitHandle(Offset screen) {
    for (final node in _doc.nodes.reversed) {
      final handle = canvasNodeOutputHandle(node, _doc.viewport);
      if ((screen - handle).distance <= 14) return node.id;
    }
    return null;
  }

  void _onScaleStart(ScaleStartDetails details) {
    _gestureMoved = false;
    _gestureStartFocal = details.localFocalPoint;
    _gestureStartViewport = _doc.viewport;

    if (details.pointerCount >= 2) {
      _mode = _GestureMode.scale;
      return;
    }
    final handleId = _hitHandle(details.localFocalPoint);
    if (handleId != null) {
      _mode = _GestureMode.connect;
      _connection = CanvasConnectionDraft(
        sourceId: handleId,
        end: details.localFocalPoint,
      );
      return;
    }
    final node = _hitNode(details.localFocalPoint);
    if (node != null) {
      _mode = _GestureMode.nodeDrag;
      _dragNodeId = node.id;
      _dragNodeStartX = node.x;
      _dragNodeStartY = node.y;
      return;
    }
    _mode = _GestureMode.pan;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final focal = details.localFocalPoint;
    if ((focal - _gestureStartFocal).distance > 4) _gestureMoved = true;

    if (_mode == _GestureMode.nodeDrag) {
      final dx = (focal.dx - _gestureStartFocal.dx) / _gestureStartViewport.zoom;
      final dy = (focal.dy - _gestureStartFocal.dy) / _gestureStartViewport.zoom;
      var x = _dragNodeStartX + dx;
      var y = _dragNodeStartY + dy;
      if (_snapEnabled) {
        x = _snap(x);
        y = _snap(y);
      }
      setState(() => _moveNode(_dragNodeId!, x, y));
      return;
    }
    if (_mode == _GestureMode.connect) {
      setState(() {
        _connection = CanvasConnectionDraft(
          sourceId: _connection!.sourceId,
          end: focal,
        );
      });
      return;
    }

    if (details.pointerCount >= 2) _mode = _GestureMode.scale;
    if (_mode == _GestureMode.scale) {
      final newZoom =
          (_gestureStartViewport.zoom * details.scale).clamp(0.2, 4.0);
      final worldX =
          (_gestureStartFocal.dx - _gestureStartViewport.x) /
              _gestureStartViewport.zoom;
      final worldY =
          (_gestureStartFocal.dy - _gestureStartViewport.y) /
              _gestureStartViewport.zoom;
      setState(() {
        _doc.viewport = CanvasViewport(
          x: focal.dx - worldX * newZoom,
          y: focal.dy - worldY * newZoom,
          zoom: newZoom,
        );
      });
      return;
    }

    // 单指空白拖动 = 平移。
    setState(() {
      _doc.viewport = _gestureStartViewport.copyWith(
        x: _gestureStartViewport.x + (focal.dx - _gestureStartFocal.dx),
        y: _gestureStartViewport.y + (focal.dy - _gestureStartFocal.dy),
      );
    });
  }

  void _onScaleEnd(ScaleEndDetails details) {
    if (_mode == _GestureMode.nodeDrag) {
      if (!_gestureMoved) {
        _selectNode(_dragNodeId!, single: true);
        setState(() => _editingNodeId = _dragNodeId);
      } else {
        _scheduleSave();
      }
    } else if (_mode == _GestureMode.connect) {
      _finishConnection();
    } else if (_mode == _GestureMode.pan) {
      if (!_gestureMoved) {
        setState(() {
          _clearSelection();
          _editingNodeId = null;
        });
      } else {
        _scheduleSave();
      }
    } else if (_mode == _GestureMode.scale) {
      _scheduleSave();
    }
    _mode = _GestureMode.none;
    _dragNodeId = null;
    _connection = null;
  }

  void _onLongPressStart(LongPressStartDetails details) {
    final node = _hitNode(details.localPosition);
    if (node != null) {
      _showNodeMenu(node);
    } else {
      setState(() {
        _selectionStart = details.localPosition;
        _selectionRect = Rect.fromPoints(
          details.localPosition,
          details.localPosition,
        );
      });
    }
  }

  void _onLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    final start = _selectionStart;
    if (start == null) return;
    setState(() {
      _selectionRect = Rect.fromPoints(start, details.localPosition);
    });
  }

  void _onLongPressEnd(LongPressEndDetails details) {
    final rect = _selectionRect;
    _selectionRect = null;
    _selectionStart = null;
    if (rect == null) return;
    setState(() {
      for (int i = 0; i < _doc.nodes.length; i++) {
        final nodeRect = canvasNodeScreenRect(_doc.nodes[i], _doc.viewport);
        _doc.nodes[i] = _doc.nodes[i].copyWith(selected: rect.overlaps(nodeRect));
      }
    });
  }

  void _moveNode(String id, double x, double y) {
    for (int i = 0; i < _doc.nodes.length; i++) {
      if (_doc.nodes[i].id == id) {
        _doc.nodes[i] = _doc.nodes[i].copyWith(x: x, y: y);
        return;
      }
    }
  }

  void _selectNode(String id, {required bool single}) {
    for (int i = 0; i < _doc.nodes.length; i++) {
      final node = _doc.nodes[i];
      _doc.nodes[i] = node.copyWith(
        selected: single ? node.id == id : (node.id == id || node.selected),
      );
    }
  }

  void _clearSelection() {
    for (int i = 0; i < _doc.nodes.length; i++) {
      if (_doc.nodes[i].selected) {
        _doc.nodes[i] = _doc.nodes[i].copyWith(selected: false);
      }
    }
  }

  void _finishConnection() {
    final sourceId = _connection?.sourceId;
    final end = _connection?.end;
    _connection = null;
    if (sourceId == null || end == null) return;
    final target = _hitNode(end);
    if (target == null || target.id == sourceId) return;
    final exists =
        _doc.edges.any((e) => e.source == sourceId && e.target == target.id);
    if (exists) return;
    setState(() {
      _doc.edges.add(
        CanvasEdge(id: _newId("e"), source: sourceId, target: target.id),
      );
    });
    _scheduleSave();
  }

  void _addNode(String type) {
    final worldX = (_canvasSize.width / 2 - _doc.viewport.x) /
            _doc.viewport.zoom -
        canvasNodeWidth / 2;
    final worldY = (_canvasSize.height / 2 - _doc.viewport.y) /
            _doc.viewport.zoom -
        canvasNodeHeight / 2;
    var x = worldX;
    var y = worldY;
    if (_snapEnabled) {
      x = _snap(x);
      y = _snap(y);
    }
    setState(() {
      _doc.nodes.add(
        CanvasNode(
          id: _newId("n"),
          type: type,
          x: x,
          y: y,
          data: {"label": _nodeTypeLabel(type)},
        ),
      );
    });
    _scheduleSave();
  }

  void _deleteNode(String id) {
    setState(() {
      _doc.nodes.removeWhere((n) => n.id == id);
      _doc.edges.removeWhere((e) => e.source == id || e.target == id);
      if (_editingNodeId == id) _editingNodeId = null;
    });
    _scheduleSave();
  }

  void _deleteSelected() {
    final ids = _doc.nodes.where((n) => n.selected).map((n) => n.id).toSet();
    if (ids.isEmpty) return;
    setState(() {
      _doc.nodes.removeWhere((n) => ids.contains(n.id));
      _doc.edges.removeWhere(
        (e) => ids.contains(e.source) || ids.contains(e.target),
      );
      if (_editingNodeId != null && ids.contains(_editingNodeId)) {
        _editingNodeId = null;
      }
    });
    _scheduleSave();
  }

  void _autoLayout() {
    const cols = 4;
    const gapX = 40.0;
    const gapY = 40.0;
    const startX = 40.0;
    const startY = 40.0;
    setState(() {
      for (int i = 0; i < _doc.nodes.length; i++) {
        final col = i % cols;
        final row = i ~/ cols;
        _doc.nodes[i] = _doc.nodes[i].copyWith(
          x: startX + col * (canvasNodeWidth + gapX),
          y: startY + row * (canvasNodeHeight + gapY),
        );
      }
    });
    _scheduleSave();
  }

  void _updateNodeData(String id, String key, String value) {
    setState(() {
      for (int i = 0; i < _doc.nodes.length; i++) {
        if (_doc.nodes[i].id == id) {
          final data = Map<String, dynamic>.from(_doc.nodes[i].data);
          data[key] = value;
          _doc.nodes[i] = _doc.nodes[i].copyWith(data: data);
          return;
        }
      }
    });
    _scheduleSave();
  }

  String? _mediaKindForNodeType(String type) {
    switch (type) {
      case CanvasNodeType.image:
        return "image";
      case CanvasNodeType.video:
        return "video";
      case CanvasNodeType.audio:
        return "audio";
      default:
        return null;
    }
  }

  Future<void> _chooseAssetFor(CanvasNode node) async {
    final kind = _mediaKindForNodeType(node.type);
    if (kind == null) return;
    final path = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => AssetLibraryPage(
          client: widget.client,
          selecting: true,
          mediaKind: kind,
        ),
      ),
    );
    if (path == null || !mounted) return;
    final mimeType = assetMimeType(path);
    if (mimeType == null) return;
    final dataType = kind == "image"
        ? "IMAGE"
        : kind == "video"
            ? "VIDEO"
            : "AUDIO";
    setState(() {
      for (int i = 0; i < _doc.nodes.length; i++) {
        if (_doc.nodes[i].id == node.id) {
          final data = Map<String, dynamic>.from(_doc.nodes[i].data);
          final outputs = Map<String, dynamic>.from(
            data["outputs"] is Map
                ? data["outputs"] as Map
                : const <String, dynamic>{},
          );
          outputs[kind] = {
            "dataType": dataType,
            "value": {"url": path, "mimeType": mimeType},
          };
          data["outputs"] = outputs;
          _doc.nodes[i] = _doc.nodes[i].copyWith(data: data);
          return;
        }
      }
    });
    _scheduleSave();
  }

  void _showAddNodePanel() {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        final l10n = AppLocalizations.of(context);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.addNode,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: CanvasNodeType.all.map((type) {
                    return ActionChip(
                      avatar: Icon(nodeIconForType(type), size: 18),
                      label: Text(_nodeTypeLabel(type)),
                      onPressed: () {
                        Navigator.pop(context);
                        _addNode(type);
                      },
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showNodeMenu(CanvasNode node) {
    final l10n = AppLocalizations.of(context);
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: ListTile(
          leading: Icon(
            Icons.delete_outline,
            color: Theme.of(context).colorScheme.error,
          ),
          title: Text(l10n.deleteNode),
          onTap: () {
            Navigator.pop(context);
            _deleteNode(node.id);
          },
        ),
      ),
    );
  }

  String _nodeTypeLabel(String type) {
    final l10n = AppLocalizations.of(context);
    switch (type) {
      case CanvasNodeType.text:
        return l10n.nodeTypeText;
      case CanvasNodeType.image:
        return l10n.nodeTypeImage;
      case CanvasNodeType.video:
        return l10n.nodeTypeVideo;
      case CanvasNodeType.audio:
        return l10n.nodeTypeAudio;
      case CanvasNodeType.imageGeneration:
        return l10n.nodeTypeImageGeneration;
      case CanvasNodeType.videoGeneration:
        return l10n.nodeTypeVideoGeneration;
      case CanvasNodeType.audioGeneration:
        return l10n.nodeTypeAudioGeneration;
      case CanvasNodeType.director3d:
        return l10n.nodeTypeDirector3d;
      case CanvasNodeType.frameAnalysis:
        return l10n.nodeTypeFrameAnalysis;
      default:
        return type;
    }
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 800), _saveNow);
  }

  Future<void> _saveNow() async {
    final files = _files;
    if (files == null) return;
    try {
      await files.writeText(_canvasPath, jsonEncode(_doc.toJson()));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("${AppLocalizations.of(context).saveFailed}: $e"),
        ),
      );
    }
  }

  CanvasNode? _editingNode() {
    for (final node in _doc.nodes) {
      if (node.id == _editingNodeId) return node;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final editingNode = _editingNode();
    final isMediaNode = editingNode != null &&
        (editingNode.type == CanvasNodeType.image ||
            editingNode.type == CanvasNodeType.video ||
            editingNode.type == CanvasNodeType.audio);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.smart_toy_outlined),
            tooltip: l10n.agent,
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => AgentPage(
                    client: widget.client,
                    directory: widget.directory,
                  ),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.article_outlined),
            tooltip: l10n.document,
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => DocumentPage(
                    client: widget.client,
                    directory: widget.directory,
                    title: widget.title,
                  ),
                ),
              );
            },
          ),
          IconButton(
            icon: Icon(_snapEnabled ? Icons.grid_on : Icons.grid_off),
            tooltip: l10n.autoLayout,
            onPressed: () => setState(() => _snapEnabled = !_snapEnabled),
          ),
          IconButton(
            icon: const Icon(Icons.auto_awesome_motion_outlined),
            tooltip: l10n.autoLayout,
            onPressed: _doc.nodes.isEmpty ? null : _autoLayout,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: l10n.deleteNode,
            onPressed: _hasSelection ? _deleteSelected : null,
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: l10n.addNode,
            onPressed: _showAddNodePanel,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(_loadError!),
                      const SizedBox(height: 8),
                      OutlinedButton(
                        onPressed: _load,
                        child: Text(l10n.retry),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          _canvasSize = Size(
                            constraints.maxWidth,
                            constraints.maxHeight,
                          );
                          return GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onScaleStart: _onScaleStart,
                            onScaleUpdate: _onScaleUpdate,
                            onScaleEnd: _onScaleEnd,
                            onLongPressStart: _onLongPressStart,
                            onLongPressMoveUpdate: _onLongPressMoveUpdate,
                            onLongPressEnd: _onLongPressEnd,
                            child: CustomPaint(
                              painter: CanvasPainter(
                                nodes: _doc.nodes,
                                edges: _doc.edges,
                                viewport: _doc.viewport,
                                colorScheme: colorScheme,
                                selectionRect: _selectionRect,
                                connection: _connection,
                              ),
                              child: SizedBox.expand(
                                child: _doc.nodes.isEmpty
                                    ? Center(
                                        child: Text(
                                          l10n.emptyCanvas,
                                          style: TextStyle(
                                            color: colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                      )
                                    : const SizedBox.shrink(),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    if (editingNode != null)
                      _NodeEditorPanel(
                        key: ValueKey(editingNode.id),
                        node: editingNode,
                        showPrompt:
                            CanvasNodeType.generation.contains(editingNode.type),
                        onLabelChanged: (v) =>
                            _updateNodeData(editingNode.id, "label", v),
                        onPromptChanged: (v) =>
                            _updateNodeData(editingNode.id, "prompt", v),
                        onChooseAsset: isMediaNode
                            ? () => _chooseAssetFor(editingNode)
                            : null,
                        onClose: () => setState(() => _editingNodeId = null),
                      ),
                  ],
                ),
    );
  }
}

class _NodeEditorPanel extends StatefulWidget {
  final CanvasNode node;
  final bool showPrompt;
  final ValueChanged<String> onLabelChanged;
  final ValueChanged<String> onPromptChanged;
  final VoidCallback? onChooseAsset;
  final VoidCallback onClose;

  const _NodeEditorPanel({
    super.key,
    required this.node,
    required this.showPrompt,
    required this.onLabelChanged,
    required this.onPromptChanged,
    required this.onChooseAsset,
    required this.onClose,
  });

  @override
  State<_NodeEditorPanel> createState() => _NodeEditorPanelState();
}

class _NodeEditorPanelState extends State<_NodeEditorPanel> {
  late final TextEditingController _labelController;
  late final TextEditingController _promptController;

  @override
  void initState() {
    super.initState();
    _labelController = TextEditingController(text: widget.node.label);
    _promptController = TextEditingController(text: widget.node.prompt);
  }

  @override
  void dispose() {
    _labelController.dispose();
    _promptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Material(
      elevation: 8,
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.nodes,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: widget.onClose,
                  ),
                ],
              ),
              TextField(
                controller: _labelController,
                decoration: InputDecoration(
                  labelText: l10n.label,
                  border: const OutlineInputBorder(),
                ),
                onChanged: widget.onLabelChanged,
              ),
              if (widget.showPrompt) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _promptController,
                  minLines: 2,
                  maxLines: 4,
                  decoration: InputDecoration(
                    labelText: l10n.prompt,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: widget.onPromptChanged,
                ),
              ],
              if (widget.onChooseAsset != null) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.photo_library_outlined),
                  label: Text(l10n.chooseFromLibrary),
                  onPressed: widget.onChooseAsset,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
