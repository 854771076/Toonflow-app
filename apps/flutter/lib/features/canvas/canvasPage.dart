import "dart:async";
import "dart:convert";
import "dart:math";

import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:forui/forui.dart";

import "../../core/apiClient.dart";
import "../../core/authService.dart";
import "../../core/workspaceFiles.dart";
import "../../shared/appLocalizations.dart";
import "../agent/agentPage.dart";
import "../assets/assetLibraryPage.dart";
import "../document/documentPage.dart";
import "../settings/settingsPage.dart";
import "../webview/webViewPage.dart";
import "canvasModel.dart";
import "canvasPainter.dart";

enum _GestureMode { none, pan, scale, nodeDrag, connect }

/// 无限画布编辑页：自绘节点/连线，支持平移、缩放、框选、连线与持久化。
class CanvasPage extends StatefulWidget {
  final ApiClient client;
  final AuthService auth;
  final String directory;
  final String title;
  final Future<void> Function() onLoggedOut;

  const CanvasPage({
    super.key,
    required this.client,
    required this.auth,
    required this.directory,
    required this.title,
    required this.onLoggedOut,
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
  bool _showEdges = true;
  bool _handMode = false;
  bool _showMiniMap = false;
  Size _canvasSize = Size.zero;
  final List<String> _undoStack = [];
  final List<String> _redoStack = [];
  String? _dragStartSnapshot;

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
  AuthSession? _session;

  bool get _hasSelection => _doc.nodes.any((n) => n.selected);

  @override
  void initState() {
    super.initState();
    _load();
    _loadSession();
  }

  Future<void> _loadSession() async {
    try {
      final session = await widget.auth.session();
      if (mounted) setState(() => _session = session);
    } catch (_) {
      // 会话获取失败时保持未登录态，不阻断画布使用。
    }
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
      final rect = node.isGroup
          ? canvasGroupScreenRect(node, _doc.viewport)
          : canvasNodeScreenRect(node, _doc.viewport);
      if (rect.contains(screen)) {
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
    final node = _handMode ? null : _hitNode(details.localFocalPoint);
    if (node != null) {
      _mode = _GestureMode.nodeDrag;
      _dragNodeId = node.id;
      _dragNodeStartX = node.x;
      _dragNodeStartY = node.y;
      _dragStartSnapshot = jsonEncode(_doc.toJson());
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
        final snapshot = _dragStartSnapshot;
        if (snapshot != null) {
          _undoStack.add(snapshot);
          if (_undoStack.length > _maxHistory) _undoStack.removeAt(0);
          _redoStack.clear();
        }
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
    _dragStartSnapshot = null;
  }

  void _onLongPressStart(LongPressStartDetails details) {
    final node = _hitNode(details.localPosition);
    if (node != null) {
      final selectedCount = _doc.nodes.where((n) => n.selected).length;
      if (selectedCount > 1 && node.selected) {
        _showSelectionMenu();
      } else {
        _showNodeMenu(node);
      }
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
        final node = _doc.nodes[i];
        final nodeRect = node.isGroup
            ? canvasGroupScreenRect(node, _doc.viewport)
            : canvasNodeScreenRect(node, _doc.viewport);
        _doc.nodes[i] = node.copyWith(selected: rect.overlaps(nodeRect));
      }
    });
  }

  void _moveNode(String id, double x, double y) {
    for (int i = 0; i < _doc.nodes.length; i++) {
      if (_doc.nodes[i].id == id) {
        final dx = x - _doc.nodes[i].x;
        final dy = y - _doc.nodes[i].y;
        final isGroup = _doc.nodes[i].isGroup;
        _doc.nodes[i] = _doc.nodes[i].copyWith(x: x, y: y);
        if (isGroup) _moveGroupChildren(id, dx, dy);
        return;
      }
    }
  }

  void _moveGroupChildren(String groupId, double dx, double dy) {
    for (int i = 0; i < _doc.nodes.length; i++) {
      if (_doc.nodes[i].parentNode == groupId) {
        _doc.nodes[i] = _doc.nodes[i].copyWith(
          x: _doc.nodes[i].x + dx,
          y: _doc.nodes[i].y + dy,
        );
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
    _pushUndo();
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
    _pushUndo();
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
    _pushUndo();
    setState(() {
      final isGroup = _doc.nodes.any((n) => n.id == id && n.isGroup);
      _doc.nodes.removeWhere((n) => n.id == id);
      _doc.edges.removeWhere((e) => e.source == id || e.target == id);
      if (isGroup) _detachGroupChildren(id);
      if (_editingNodeId == id) _editingNodeId = null;
    });
    _scheduleSave();
  }

  void _deleteSelected() {
    final ids = _doc.nodes.where((n) => n.selected).map((n) => n.id).toSet();
    if (ids.isEmpty) return;
    _pushUndo();
    setState(() {
      final groupIds = _doc.nodes
          .where((n) => ids.contains(n.id) && n.isGroup)
          .map((n) => n.id)
          .toSet();
      _doc.nodes.removeWhere((n) => ids.contains(n.id));
      _doc.edges.removeWhere(
        (e) => ids.contains(e.source) || ids.contains(e.target),
      );
      for (final groupId in groupIds) {
        _detachGroupChildren(groupId);
      }
      if (_editingNodeId != null && ids.contains(_editingNodeId)) {
        _editingNodeId = null;
      }
    });
    _scheduleSave();
  }

  void _detachGroupChildren(String groupId) {
    for (int i = 0; i < _doc.nodes.length; i++) {
      if (_doc.nodes[i].parentNode == groupId) {
        _doc.nodes[i] = _doc.nodes[i].copyWith(parentNode: null);
      }
    }
  }

  void _duplicateNode(CanvasNode node) {
    _pushUndo();
    setState(() {
      _doc.nodes.add(
        CanvasNode(
          id: _newId("n"),
          type: node.type,
          x: node.x + canvasNodeWidth + 24,
          y: node.y + 24,
          data: Map<String, dynamic>.from(node.data),
        ),
      );
    });
    _scheduleSave();
  }

  void _duplicateSelection() {
    final selected =
        _doc.nodes.where((n) => n.selected && !n.isGroup).toList();
    if (selected.isEmpty) return;
    _pushUndo();
    setState(() {
      for (final node in selected) {
        _doc.nodes.add(
          CanvasNode(
            id: _newId("n"),
            type: node.type,
            x: node.x + canvasNodeWidth + 24,
            y: node.y + 24,
            data: Map<String, dynamic>.from(node.data),
          ),
        );
      }
    });
    _scheduleSave();
  }

  void _showSelectionMenu() {
    final l10n = AppLocalizations.of(context);
    final selected = _doc.nodes.where((n) => n.selected).toList();
    final selectedCount = selected.length;
    final hasGroup = selected.any((n) => n.isGroup);
    final canGroup = selected.length >= 2 && selected.every((n) => !n.isGroup);
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (canGroup)
              ListTile(
                leading: const Icon(FLucideIcons.folderPlus),
                title: Text(l10n.groupSelection),
                onTap: () {
                  Navigator.pop(context);
                  _groupSelection();
                },
              ),
            if (hasGroup)
              ListTile(
                leading: const Icon(FLucideIcons.folderMinus),
                title: Text(l10n.ungroupSelection),
                onTap: () {
                  Navigator.pop(context);
                  _ungroupSelection();
                },
              ),
            if (hasGroup)
              ListTile(
                leading: const Icon(FLucideIcons.palette),
                title: Text(l10n.groupColor),
                onTap: () {
                  Navigator.pop(context);
                  _changeGroupColor();
                },
              ),
            ListTile(
              leading: const Icon(FLucideIcons.copy),
              title: Text(l10n.duplicateNode),
              onTap: () {
                Navigator.pop(context);
                _duplicateSelection();
              },
            ),
            ListTile(
              leading: const Icon(FLucideIcons.layoutGrid),
              title: Text(l10n.organizeSelection),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.pop(context);
                _showArrangeMenu();
              },
            ),
            ListTile(
              leading: Icon(
                FLucideIcons.trash2,
                color: context.theme.colors.destructive,
              ),
              title: Text("${l10n.deleteSelection} ($selectedCount)"),
              onTap: () {
                Navigator.pop(context);
                _deleteSelected();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _groupSelection() {
    final l10n = AppLocalizations.of(context);
    final selected =
        _doc.nodes.where((n) => n.selected && !n.isGroup).toList();
    if (selected.length < 2) return;
    final minX = selected.map((n) => n.x).reduce(min);
    final minY = selected.map((n) => n.y).reduce(min);
    final maxX =
        selected.map((n) => n.x + canvasNodeWidth).reduce(max);
    final maxY = selected
        .map((n) => n.y + canvasNodeDisplayHeight(n))
        .reduce(max);

    const padX = 24.0;
    const padTop = 40.0;
    const padBottom = 24.0;
    final groupId = _newId("g");
    final groupX = minX - padX;
    final groupY = minY - padTop;
    final groupW = (maxX - minX) + padX * 2;
    final groupH = (maxY - minY) + padTop + padBottom;

    _pushUndo();
    setState(() {
      for (int i = 0; i < _doc.nodes.length; i++) {
        if (_doc.nodes[i].selected && !_doc.nodes[i].isGroup) {
          _doc.nodes[i] = _doc.nodes[i].copyWith(parentNode: groupId);
        }
      }
      _doc.nodes.add(
        CanvasNode(
          id: groupId,
          type: CanvasNodeType.canvasGroup,
          x: groupX,
          y: groupY,
          data: {
            "label": l10n.group,
            "groupColor": "#808080",
            "groupOpacity": 25,
          },
          width: groupW,
          height: groupH,
        ),
      );
      _clearSelection();
      _selectNode(groupId, single: true);
    });
    _scheduleSave();
  }

  void _ungroupSelection() {
    final groupIds =
        _doc.nodes.where((n) => n.selected && n.isGroup).map((n) => n.id).toSet();
    if (groupIds.isEmpty) return;
    _pushUndo();
    setState(() {
      for (int i = 0; i < _doc.nodes.length; i++) {
        final parent = _doc.nodes[i].parentNode;
        if (parent != null && groupIds.contains(parent)) {
          _doc.nodes[i] = _doc.nodes[i].copyWith(parentNode: null);
        }
      }
      _doc.nodes.removeWhere((n) => groupIds.contains(n.id));
    });
    _scheduleSave();
  }

  static const List<String> _groupColors = [
    "#808080",
    "#ef4444",
    "#f97316",
    "#eab308",
    "#22c55e",
    "#06b6d4",
    "#3b82f6",
    "#8b5cf6",
    "#ec4899",
    "#a16207",
    "#ffffff",
  ];

  void _changeGroupColor() {
    if (!_doc.nodes.any((n) => n.selected && n.isGroup)) return;
    final l10n = AppLocalizations.of(context);
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.groupColor,
                style: context.theme.typography.base,
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: _groupColors.map((hex) {
                  return InkWell(
                    onTap: () {
                      Navigator.pop(context);
                      _applyGroupColor(hex);
                    },
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: hexToColor(hex),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: context.theme.colors.border,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _applyGroupColor(String hex) {
    if (!_doc.nodes.any((n) => n.selected && n.isGroup)) return;
    _pushUndo();
    setState(() {
      for (int i = 0; i < _doc.nodes.length; i++) {
        if (_doc.nodes[i].selected && _doc.nodes[i].isGroup) {
          final data = Map<String, dynamic>.from(_doc.nodes[i].data);
          data["groupColor"] = hex;
          _doc.nodes[i] = _doc.nodes[i].copyWith(data: data);
        }
      }
    });
    _scheduleSave();
  }

  static const int _maxHistory = 50;

  void _pushUndo() {
    _undoStack.add(jsonEncode(_doc.toJson()));
    if (_undoStack.length > _maxHistory) _undoStack.removeAt(0);
    _redoStack.clear();
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    _redoStack.add(jsonEncode(_doc.toJson()));
    final snapshot = _undoStack.removeLast();
    setState(() {
      _doc = CanvasDocument.fromJson(
        jsonDecode(snapshot) as Map<String, dynamic>,
      );
      _editingNodeId = null;
    });
    _scheduleSave();
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    _undoStack.add(jsonEncode(_doc.toJson()));
    final snapshot = _redoStack.removeLast();
    setState(() {
      _doc = CanvasDocument.fromJson(
        jsonDecode(snapshot) as Map<String, dynamic>,
      );
      _editingNodeId = null;
    });
    _scheduleSave();
  }

  void _autoLayout() {
    const cols = 4;
    const gapX = 40.0;
    const gapY = 40.0;
    const startX = 40.0;
    const startY = 40.0;
    _pushUndo();
    setState(() {
      int index = 0;
      for (int i = 0; i < _doc.nodes.length; i++) {
        if (_doc.nodes[i].isGroup) continue;
        final col = index % cols;
        final row = index ~/ cols;
        _doc.nodes[i] = _doc.nodes[i].copyWith(
          x: startX + col * (canvasNodeWidth + gapX),
          y: startY + row * (canvasNodeHeight + gapY),
        );
        index++;
      }
    });
    _scheduleSave();
  }

  List<CanvasNode> _arrangeTargets() {
    final selected =
        _doc.nodes.where((n) => n.selected && !n.isGroup).toList();
    if (selected.isNotEmpty) return selected;
    return _doc.nodes.where((n) => !n.isGroup).toList();
  }

  void _arrangeHorizontal() {
    final targets = _arrangeTargets()..sort((a, b) {
      final byX = a.x.compareTo(b.x);
      return byX != 0 ? byX : a.y.compareTo(b.y);
    });
    if (targets.length < 2) return;
    final originX = targets.map((n) => n.x).reduce(min);
    final originY = targets.map((n) => n.y).reduce(min);
    _pushUndo();
    setState(() {
      for (int i = 0; i < targets.length; i++) {
        _moveNode(
          targets[i].id,
          originX + i * (canvasNodeWidth + 80),
          originY,
        );
      }
    });
    _scheduleSave();
  }

  void _arrangeVertical() {
    final targets = _arrangeTargets()..sort((a, b) {
      final byY = a.y.compareTo(b.y);
      return byY != 0 ? byY : a.x.compareTo(b.x);
    });
    if (targets.length < 2) return;
    final originX = targets.map((n) => n.x).reduce(min);
    final originY = targets.map((n) => n.y).reduce(min);
    _pushUndo();
    setState(() {
      for (int i = 0; i < targets.length; i++) {
        _moveNode(
          targets[i].id,
          originX,
          originY + i * (canvasNodeHeight + 80),
        );
      }
    });
    _scheduleSave();
  }

  void _arrangeGrid() {
    final targets = _arrangeTargets();
    if (targets.length < 2) return;
    final cols = sqrt(targets.length).ceil();
    final originX = targets.map((n) => n.x).reduce(min);
    final originY = targets.map((n) => n.y).reduce(min);
    _pushUndo();
    setState(() {
      for (int i = 0; i < targets.length; i++) {
        final col = i % cols;
        final row = i ~/ cols;
        _moveNode(
          targets[i].id,
          originX + col * (canvasNodeWidth + 80),
          originY + row * (canvasNodeHeight + 80),
        );
      }
    });
    _scheduleSave();
  }

  void _showArrangeMenu() {
    final l10n = AppLocalizations.of(context);
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.horizontal_distribute),
              title: Text(l10n.arrangeHorizontal),
              onTap: () {
                Navigator.pop(context);
                _arrangeHorizontal();
              },
            ),
            ListTile(
              leading: const Icon(Icons.vertical_distribute),
              title: Text(l10n.arrangeVertical),
              onTap: () {
                Navigator.pop(context);
                _arrangeVertical();
              },
            ),
            ListTile(
              leading: const Icon(Icons.grid_view),
              title: Text(l10n.arrangeGrid),
              onTap: () {
                Navigator.pop(context);
                _arrangeGrid();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _fitView() {
    if (_canvasSize.isEmpty) return;
    if (_doc.nodes.isEmpty) {
      setState(() => _doc.viewport = const CanvasViewport());
      return;
    }
    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = -double.infinity;
    var maxY = -double.infinity;
    for (final node in _doc.nodes) {
      minX = min(minX, node.x);
      minY = min(minY, node.y);
      maxX = max(maxX, node.x + canvasNodeWidth);
      maxY = max(maxY, node.y + canvasNodeHeight);
    }
    final worldW = maxX - minX;
    final worldH = maxY - minY;
    final zoom = min(
      (_canvasSize.width - 80) / worldW,
      (_canvasSize.height - 80) / worldH,
    ).clamp(0.2, 4.0);
    setState(() {
      _doc.viewport = CanvasViewport(
        x: (_canvasSize.width - worldW * zoom) / 2 - minX * zoom,
        y: (_canvasSize.height - worldH * zoom) / 2 - minY * zoom,
        zoom: zoom,
      );
    });
    _scheduleSave();
  }

  void _zoomBy(double factor) {
    if (_canvasSize.isEmpty) return;
    final cx = _canvasSize.width / 2;
    final cy = _canvasSize.height / 2;
    final newZoom = (_doc.viewport.zoom * factor).clamp(0.2, 4.0);
    final worldX = (cx - _doc.viewport.x) / _doc.viewport.zoom;
    final worldY = (cy - _doc.viewport.y) / _doc.viewport.zoom;
    setState(() {
      _doc.viewport = CanvasViewport(
        x: cx - worldX * newZoom,
        y: cy - worldY * newZoom,
        zoom: newZoom,
      );
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

  Widget _buildCanvasEmpty(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    const actions = [
      CanvasNodeType.imageGeneration,
      CanvasNodeType.videoGeneration,
      CanvasNodeType.audioGeneration,
    ];
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.touch_app_outlined, size: 20),
              const SizedBox(width: 8),
              Text(
                l10n.doubleClickToCreate,
                style: TextStyle(
                  color: context.theme.colors.mutedForeground,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: actions.map((type) {
              return FButton(
                onPress: () => _addNode(type),
                variant: .outline,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(nodeIconForType(type), size: 18),
                    const SizedBox(width: 8),
                    Text(_nodeTypeLabel(type)),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  void _openUrl(String url, String title) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WebViewPage(url: url, title: title),
      ),
    );
  }

  void _showContact(String title, String url, String tip) {
    final l10n = AppLocalizations.of(context);
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(tip),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: url));
              Navigator.pop(dialogContext);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(l10n.linkCopied)),
              );
            },
            child: Text(l10n.copyLink),
          ),
        ],
      ),
    );
  }

  void _showHelpMenu() {
    final l10n = AppLocalizations.of(context);
    const tutorialUrl =
        "https://qcn7xdsqgc4z.feishu.cn/docx/RXFqdgR2Xo0dXZxGfd0cZCGgnwf";
    const bugUrl =
        "https://docs.qq.com/smartsheet/form/EmvmQBrmlPmr%2Fss_vsqk2v%2FvhiGzE?tab=ss_vsqk2v";
    const communityUrl =
        "https://work.weixin.qq.com/u/vc36adcc89845edcbe?v=5.0.3.63936&bb=85b8d228e8";
    const businessUrl =
        "https://work.weixin.qq.com/u/vc0f54596c5837d05a?v=5.0.8.70675";
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.menu_book_outlined),
              title: Text(l10n.helpTutorial),
              onTap: () {
                Navigator.pop(sheetContext);
                _openUrl(tutorialUrl, l10n.helpTutorial);
              },
            ),
            ListTile(
              leading: const Icon(Icons.bug_report_outlined),
              title: Text(l10n.reportBug),
              onTap: () {
                Navigator.pop(sheetContext);
                _openUrl(bugUrl, l10n.reportBug);
              },
            ),
            ListTile(
              leading: const Icon(Icons.chat_outlined),
              title: Text(l10n.joinCommunity),
              onTap: () {
                Navigator.pop(sheetContext);
                _showContact(
                  l10n.joinCommunity,
                  communityUrl,
                  l10n.communityTip,
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.work_outline),
              title: Text(l10n.businessCooperation),
              onTap: () {
                Navigator.pop(sheetContext);
                _showContact(
                  l10n.businessCooperation,
                  businessUrl,
                  l10n.businessTip,
                );
              },
            ),
          ],
        ),
      ),
    );
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
                  style: context.theme.typography.body.md,
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (node.isGroup) ...[
              ListTile(
                leading: const Icon(FLucideIcons.folderMinus),
                title: Text(l10n.ungroupSelection),
                onTap: () {
                  Navigator.pop(context);
                  setState(() => _selectNode(node.id, single: true));
                  _ungroupSelection();
                },
              ),
              ListTile(
                leading: const Icon(FLucideIcons.palette),
                title: Text(l10n.groupColor),
                onTap: () {
                  Navigator.pop(context);
                  setState(() => _selectNode(node.id, single: true));
                  _changeGroupColor();
                },
              ),
            ] else
              ListTile(
                leading: const Icon(FLucideIcons.copy),
                title: Text(l10n.duplicateNode),
                onTap: () {
                  Navigator.pop(context);
                  _duplicateNode(node);
                },
              ),
            ListTile(
              leading: Icon(
                FLucideIcons.trash2,
                color: context.theme.colors.destructive,
              ),
              title: Text(l10n.deleteNode),
              onTap: () {
                Navigator.pop(context);
                _deleteNode(node.id);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _openAssetLibrary() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AssetLibraryPage(client: widget.client),
      ),
    );
  }

  void _showZoomMenu() {
    final l10n = AppLocalizations.of(context);
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.zoom_in),
              title: Text(l10n.zoomIn),
              onTap: () {
                Navigator.pop(context);
                _zoomBy(1.2);
              },
            ),
            ListTile(
              leading: const Icon(Icons.zoom_out),
              title: Text(l10n.zoomOut),
              onTap: () {
                Navigator.pop(context);
                _zoomBy(1 / 1.2);
              },
            ),
            ListTile(
              leading: const Icon(Icons.zoom_out_map),
              title: Text(l10n.fitView),
              onTap: () {
                Navigator.pop(context);
                _fitView();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showWorkspaceMenu() {
    final l10n = AppLocalizations.of(context);
    final navigator = Navigator.of(context);
    final session = _session;
    final signedIn = session?.authenticated == true;
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (signedIn) ...[
              ListTile(
                leading: const CircleAvatar(child: Icon(FLucideIcons.user)),
                title: Text(session?.username ?? session?.sub ?? ""),
                subtitle:
                    session?.email == null ? null : Text(session!.email!),
              ),
              ListTile(
                leading: const Icon(FLucideIcons.settings),
                title: Text(l10n.accountSettings),
                onTap: () {
                  Navigator.pop(sheetContext);
                  navigator.push(
                    MaterialPageRoute(
                      builder: (_) => SettingsPage(client: widget.client),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(FLucideIcons.wallet),
                title: Text(l10n.rechargeBalance),
                onTap: () {
                  Navigator.pop(sheetContext);
                  navigator.push(
                    MaterialPageRoute(
                      builder: (_) => SettingsPage(client: widget.client),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(FLucideIcons.logOut),
                title: Text(l10n.logout),
                onTap: () => _handleLogout(sheetContext),
              ),
              const Divider(),
            ],
            ListTile(
              leading: const Icon(FLucideIcons.settings),
              title: Text(l10n.settings),
              onTap: () {
                Navigator.pop(sheetContext);
                navigator.push(
                  MaterialPageRoute(
                    builder: (_) => SettingsPage(client: widget.client),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(FLucideIcons.logOut),
              title: Text(l10n.exitProject),
              onTap: () {
                Navigator.pop(sheetContext);
                navigator.popUntil((route) => route.isFirst);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleLogout(BuildContext sheetContext) async {
    Navigator.pop(sheetContext);
    await widget.auth.logout();
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
    await widget.onLoggedOut();
  }

  void _focusNode(CanvasNode node) {
    if (_canvasSize.isEmpty) return;
    final centerX = node.x + canvasNodeWidth / 2;
    final centerY = node.y + canvasNodeHeight / 2;
    setState(() {
      _doc.viewport = CanvasViewport(
        x: _canvasSize.width / 2 - centerX * _doc.viewport.zoom,
        y: _canvasSize.height / 2 - centerY * _doc.viewport.zoom,
        zoom: _doc.viewport.zoom,
      );
      _selectNode(node.id, single: true);
      _editingNodeId = node.id;
    });
  }

  void _showNodeSearch() {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController();
    String query = "";
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          final nodes = _doc.nodes.where((n) {
            final q = query.trim().toLowerCase();
            if (q.isEmpty) return true;
            return n.label.toLowerCase().contains(q) ||
                _nodeTypeLabel(n.type).toLowerCase().contains(q);
          }).toList();
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: TextField(
                      controller: controller,
                      autofocus: true,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search),
                        hintText: l10n.searchNode,
                      ),
                      onChanged: (v) => setSheetState(() => query = v),
                    ),
                  ),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 320),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: nodes.length,
                      itemBuilder: (context, i) {
                        final node = nodes[i];
                        return ListTile(
                          leading: const Icon(Icons.crop_square),
                          title: Text(
                            node.label.isEmpty
                                ? _nodeTypeLabel(node.type)
                                : node.label,
                          ),
                          subtitle: Text(_nodeTypeLabel(node.type)),
                          onTap: () {
                            Navigator.pop(context);
                            _focusNode(node);
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCanvasToolbar(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final surface = Theme.of(context).colorScheme.surface;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _toolbarButton(
            context,
            Icons.undo,
            l10n.undo,
            _undoStack.isEmpty ? null : _undo,
          ),
          _toolbarButton(
            context,
            Icons.redo,
            l10n.redo,
            _redoStack.isEmpty ? null : _redo,
          ),
          _toolbarButton(
            context,
            Icons.folder_outlined,
            l10n.assetLibrary,
            _openAssetLibrary,
          ),
          _toolbarButton(
            context,
            _handMode ? Icons.back_hand : Icons.near_me,
            _handMode ? l10n.handTool : l10n.moveTool,
            () => setState(() => _handMode = !_handMode),
          ),
          _toolbarButton(
            context,
            Icons.search,
            l10n.searchNode,
            _doc.nodes.isEmpty ? null : _showNodeSearch,
          ),
          _toolbarButton(
            context,
            Icons.help_outline,
            l10n.help,
            _showHelpMenu,
          ),
          _toolbarButton(
            context,
            Icons.dashboard_outlined,
            l10n.autoLayout,
            _doc.nodes.isEmpty ? null : _autoLayout,
          ),
          _toolbarButton(
            context,
            _snapEnabled ? Icons.grid_on : Icons.grid_off,
            l10n.snapToGrid,
            () => setState(() => _snapEnabled = !_snapEnabled),
          ),
          _toolbarButton(
            context,
            _showEdges ? Icons.timeline : Icons.timeline_outlined,
            l10n.showEdges,
            () => setState(() => _showEdges = !_showEdges),
          ),
          _toolbarButton(
            context,
            Icons.zoom_out_map,
            l10n.fitView,
            _doc.nodes.isEmpty ? null : _fitView,
          ),
          _toolbarButton(
            context,
            _showMiniMap ? Icons.map : Icons.map_outlined,
            l10n.showMiniMap,
            () => setState(() => _showMiniMap = !_showMiniMap),
          ),
          TextButton(
            onPressed: _showZoomMenu,
            style: TextButton.styleFrom(
              minimumSize: Size.zero,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text("${(_doc.viewport.zoom * 100).round()}%"),
          ),
        ],
      ),
    );
  }

  Widget _toolbarButton(
    BuildContext context,
    IconData icon,
    String tooltip,
    VoidCallback? onPressed,
  ) {
    return IconButton(
      icon: Icon(icon, size: 20),
      tooltip: tooltip,
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.all(8),
      constraints: const BoxConstraints(),
    );
  }

  Widget _buildMiniMap(ColorScheme colorScheme) {
    return IgnorePointer(
      child: Container(
        width: 160,
        height: 120,
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colorScheme.outline),
        ),
        clipBehavior: Clip.antiAlias,
        child: CustomPaint(
          painter: _MiniMapPainter(
            nodes: _doc.nodes,
            viewport: _doc.viewport,
            colorScheme: colorScheme,
          ),
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
    return FScaffold(
      header: FHeader(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FHeaderAction(
              icon: const Icon(FLucideIcons.menu),
              semanticsTooltip: l10n.settings,
              onPress: _showWorkspaceMenu,
            ),
            const SizedBox(width: 4),
            Text(widget.title),
          ],
        ),
        suffixes: [
          FHeaderAction(
            icon: const Icon(FLucideIcons.bot),
            semanticsTooltip: l10n.agent,
            onPress: () {
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
          FHeaderAction(
            icon: const Icon(FLucideIcons.fileText),
            semanticsTooltip: l10n.document,
            onPress: () {
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
          FHeaderAction(
            icon: const Icon(FLucideIcons.trash2),
            semanticsTooltip: l10n.deleteNode,
            onPress: _hasSelection ? _deleteSelected : null,
          ),
          FHeaderAction(
            icon: const Icon(FLucideIcons.layoutGrid),
            semanticsTooltip: l10n.autoLayout,
            onPress: _doc.nodes.isEmpty ? null : _showArrangeMenu,
          ),
          FHeaderAction(
            icon: const Icon(FLucideIcons.plus),
            semanticsTooltip: l10n.addNode,
            onPress: _showAddNodePanel,
          ),
        ],
      ),
      childPad: false,
      child: _loading
          ? const Center(child: FCircularProgress())
          : _loadError != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(_loadError!),
                      const SizedBox(height: 8),
                      FButton(
                        onPress: _load,
                        variant: .outline,
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
                          return Stack(
                            children: [
                              Positioned.fill(
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onScaleStart: _onScaleStart,
                                  onScaleUpdate: _onScaleUpdate,
                                  onScaleEnd: _onScaleEnd,
                                  onLongPressStart: _onLongPressStart,
                                  onLongPressMoveUpdate: _onLongPressMoveUpdate,
                                  onLongPressEnd: _onLongPressEnd,
                                  onDoubleTap:
                                      _doc.nodes.isEmpty ? _showAddNodePanel : null,
                                  child: CustomPaint(
                                    painter: CanvasPainter(
                                      nodes: _doc.nodes,
                                      edges: _doc.edges,
                                      viewport: _doc.viewport,
                                      colorScheme: colorScheme,
                                      showEdges: _showEdges,
                                      selectionRect: _selectionRect,
                                      connection: _connection,
                                    ),
                                    child: SizedBox.expand(
                                      child: _doc.nodes.isEmpty
                                          ? _buildCanvasEmpty(context)
                                          : const SizedBox.shrink(),
                                    ),
                                  ),
                                ),
                              ),
                              Positioned(
                                left: 12,
                                bottom: 12,
                                child: _buildCanvasToolbar(context),
                              ),
                              if (_showMiniMap)
                                Positioned(
                                  right: 12,
                                  bottom: 12,
                                  child: _buildMiniMap(colorScheme),
                                ),
                            ],
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
    return FCard(
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
                      style: context.theme.typography.body.md,
                    ),
                  ),
                  FButton.icon(
                    onPress: widget.onClose,
                    variant: .ghost,
                    semanticsTooltip: l10n.cancel,
                    child: const Icon(FLucideIcons.x),
                  ),
                ],
              ),
              FTextField(
                control: FTextFieldControl.managed(
                  controller: _labelController,
                  onChange: (v) => widget.onLabelChanged(v.text),
                ),
                label: Text(l10n.label),
              ),
              if (widget.showPrompt) ...[
                const SizedBox(height: 12),
                FTextField(
                  control: FTextFieldControl.managed(
                    controller: _promptController,
                    onChange: (v) => widget.onPromptChanged(v.text),
                  ),
                  label: Text(l10n.prompt),
                  minLines: 2,
                  maxLines: 4,
                ),
              ],
              if (widget.onChooseAsset != null) ...[
                const SizedBox(height: 12),
                FButton(
                  onPress: widget.onChooseAsset,
                  variant: .outline,
                  prefix: const Icon(FLucideIcons.image),
                  child: Text(l10n.chooseFromLibrary),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 画布右下角缩略图：绘制节点缩略框与当前视口框。
class _MiniMapPainter extends CustomPainter {
  _MiniMapPainter({
    required this.nodes,
    required this.viewport,
    required this.colorScheme,
  });

  final List<CanvasNode> nodes;
  final CanvasViewport viewport;
  final ColorScheme colorScheme;

  @override
  void paint(Canvas canvas, Size size) {
    if (nodes.isEmpty) return;
    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = -double.infinity;
    var maxY = -double.infinity;
    for (final node in nodes) {
      minX = min(minX, node.x);
      minY = min(minY, node.y);
      maxX = max(maxX, node.x + canvasNodeWidth);
      maxY = max(maxY, node.y + canvasNodeHeight);
    }
    final worldW = maxX - minX;
    final worldH = maxY - minY;
    if (worldW <= 0 || worldH <= 0) return;

    const pad = 8.0;
    final scale = min(
      (size.width - pad * 2) / worldW,
      (size.height - pad * 2) / worldH,
    );

    final nodePaint = Paint()..color = colorScheme.primary;
    for (final node in nodes) {
      canvas.drawRect(
        Rect.fromLTWH(
          pad + (node.x - minX) * scale,
          pad + (node.y - minY) * scale,
          canvasNodeWidth * scale,
          canvasNodeHeight * scale,
        ),
        nodePaint,
      );
    }

    final vx = -viewport.x / viewport.zoom;
    final vy = -viewport.y / viewport.zoom;
    final vw = size.width / viewport.zoom;
    final vh = size.height / viewport.zoom;
    canvas.drawRect(
      Rect.fromLTWH(
        pad + (vx - minX) * scale,
        pad + (vy - minY) * scale,
        vw * scale,
        vh * scale,
      ),
      Paint()
        ..color = colorScheme.onSurface
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
  }

  @override
  bool shouldRepaint(_MiniMapPainter oldDelegate) =>
      oldDelegate.nodes != nodes || oldDelegate.viewport != viewport;
}
