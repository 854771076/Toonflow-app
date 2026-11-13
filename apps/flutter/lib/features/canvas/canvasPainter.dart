import "package:flutter/material.dart";

import "../../shared/designTokens.dart";
import "canvasModel.dart";

/// 节点卡片基准尺寸（世界坐标，随 viewport.zoom 缩放）。
const double canvasNodeWidth = 200;
const double canvasNodeHeight = 64;
const double canvasNodePromptHeight = 84;

/// 网格对齐步长（世界坐标）。
const double canvasSnapStep = 16;

/// 连线拖拽中的临时状态。
class CanvasConnectionDraft {
  final String sourceId;
  final Offset end;

  const CanvasConnectionDraft({required this.sourceId, required this.end});
}

/// 节点实际显示高度：生成类节点带 prompt 时略高。
double canvasNodeDisplayHeight(CanvasNode node) =>
    CanvasNodeType.generation.contains(node.type) && node.prompt.isNotEmpty
        ? canvasNodePromptHeight
        : canvasNodeHeight;

/// 节点在屏幕上的矩形。
Rect canvasNodeScreenRect(CanvasNode node, CanvasViewport viewport) {
  final w = canvasNodeWidth * viewport.zoom;
  final h = canvasNodeDisplayHeight(node) * viewport.zoom;
  return Rect.fromLTWH(
    node.x * viewport.zoom + viewport.x,
    node.y * viewport.zoom + viewport.y,
    w,
    h,
  );
}

/// 节点输出句柄在屏幕上的位置（右侧边缘中点）。
Offset canvasNodeOutputHandle(CanvasNode node, CanvasViewport viewport) {
  final rect = canvasNodeScreenRect(node, viewport);
  return Offset(rect.right, rect.center.dy);
}

/// 分组容器的屏幕矩形（宽高取自节点字段，缺失时回退到单个节点尺寸）。
Rect canvasGroupScreenRect(CanvasNode node, CanvasViewport viewport) {
  final w = (node.width ?? canvasNodeWidth) * viewport.zoom;
  final h = (node.height ?? canvasNodeHeight) * viewport.zoom;
  return Rect.fromLTWH(
    node.x * viewport.zoom + viewport.x,
    node.y * viewport.zoom + viewport.y,
    w,
    h,
  );
}

/// 解析 #RRGGBB / #RGB 十六进制颜色，失败时回退到主色。
Color hexToColor(String hex) {
  var value = hex.replaceFirst("#", "");
  if (value.length == 3) {
    value = value.split("").map((c) => "$c$c").join();
  }
  if (value.length == 6) value = "FF$value";
  final parsed = int.tryParse(value, radix: 16);
  return parsed == null ? DesignTokens.primary : Color(parsed);
}

/// 节点类型对应的图标。
IconData nodeIconForType(String type) {
  switch (type) {
    case CanvasNodeType.text:
      return Icons.notes;
    case CanvasNodeType.image:
      return Icons.image_outlined;
    case CanvasNodeType.video:
      return Icons.movie_outlined;
    case CanvasNodeType.audio:
      return Icons.audiotrack;
    case CanvasNodeType.imageGeneration:
      return Icons.auto_awesome_outlined;
    case CanvasNodeType.videoGeneration:
      return Icons.movie_creation_outlined;
    case CanvasNodeType.audioGeneration:
      return Icons.graphic_eq;
    case CanvasNodeType.director3d:
      return Icons.view_in_ar_outlined;
    case CanvasNodeType.frameAnalysis:
      return Icons.filter_frames_outlined;
    default:
      return Icons.widgets_outlined;
  }
}

/// 自绘无限画布：背景网格、连线、节点卡片、框选矩形与拖拽连线。
class CanvasPainter extends CustomPainter {
  CanvasPainter({
    required this.nodes,
    required this.edges,
    required this.viewport,
    required this.colorScheme,
    required this.showEdges,
    this.selectionRect,
    this.connection,
  });

  final List<CanvasNode> nodes;
  final List<CanvasEdge> edges;
  final CanvasViewport viewport;
  final ColorScheme colorScheme;
  final bool showEdges;
  final Rect? selectionRect;
  final CanvasConnectionDraft? connection;

  @override
  void paint(Canvas canvas, Size size) {
    _paintGrid(canvas, size);
    if (showEdges) _paintEdges(canvas);
    _paintGroups(canvas);
    _paintNodes(canvas);
    if (connection != null) _paintConnection(canvas);
    if (selectionRect != null) _paintSelectionRect(canvas);
  }

  void _paintGroups(Canvas canvas) {
    for (final node in nodes) {
      if (!node.isGroup) continue;
      final rect = canvasGroupScreenRect(node, viewport);
      final color = hexToColor(node.groupColor);
      final rrect = RRect.fromRectAndRadius(
        rect,
        Radius.circular(DesignTokens.radius * viewport.zoom),
      );
      canvas.drawRRect(
        rrect,
        Paint()
          ..color = color.withValues(
            alpha: (node.groupOpacity / 100).clamp(0.0, 1.0),
          ),
      );
      canvas.drawRRect(
        rrect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = color,
      );
      if (node.label.isNotEmpty) {
        _paintText(
          canvas,
          node.label,
          Offset(rect.left + 8 * viewport.zoom, rect.top + 4 * viewport.zoom),
          rect.width - 16 * viewport.zoom,
          TextStyle(
            color: color,
            fontSize: 11 * viewport.zoom,
            fontWeight: FontWeight.w600,
          ),
        );
      }
    }
  }

  void _paintGrid(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = colorScheme.outlineVariant.withValues(alpha: 0.4)
      ..strokeWidth = 1;

    // 网格间距固定为屏幕 20px，缩放时保持视觉密度稳定。
    const screenStep = 20.0;
    final worldStep = screenStep / viewport.zoom;
    final worldLeft = (0 - viewport.x) / viewport.zoom;
    final worldTop = (0 - viewport.y) / viewport.zoom;
    final worldRight = (size.width - viewport.x) / viewport.zoom;
    final worldBottom = (size.height - viewport.y) / viewport.zoom;

    for (double wx = (worldLeft / worldStep).floorToDouble() * worldStep;
        wx <= worldRight;
        wx += worldStep) {
      final sx = wx * viewport.zoom + viewport.x;
      canvas.drawLine(Offset(sx, 0), Offset(sx, size.height), paint);
    }
    for (double wy = (worldTop / worldStep).floorToDouble() * worldStep;
        wy <= worldBottom;
        wy += worldStep) {
      final sy = wy * viewport.zoom + viewport.y;
      canvas.drawLine(Offset(0, sy), Offset(size.width, sy), paint);
    }
  }

  void _paintEdges(Canvas canvas) {
    final nodeById = {for (final node in nodes) node.id: node};
    final paint = Paint()
      ..color = colorScheme.outline
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    for (final edge in edges) {
      final source = nodeById[edge.source];
      final target = nodeById[edge.target];
      if (source == null || target == null) continue;
      final p1 = canvasNodeOutputHandle(source, viewport);
      final p2 = Offset(
        target.x * viewport.zoom + viewport.x,
        target.y * viewport.zoom + viewport.y +
            canvasNodeDisplayHeight(target) * viewport.zoom / 2,
      );
      final dx = ((p2.dx - p1.dx).abs() * 0.5).clamp(24.0, 120.0);
      final path = Path()
        ..moveTo(p1.dx, p1.dy)
        ..cubicTo(p1.dx + dx, p1.dy, p2.dx - dx, p2.dy, p2.dx, p2.dy);
      canvas.drawPath(path, paint);
    }
  }

  void _paintNodes(Canvas canvas) {
    for (final node in nodes) {
      final rect = canvasNodeScreenRect(node, viewport);
      final rrect = RRect.fromRectAndRadius(
        rect,
        Radius.circular(DesignTokens.radius * viewport.zoom),
      );

      final fill = Paint()..color = colorScheme.surfaceContainerHighest;
      final border = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = node.selected ? 2 : 1
        ..color = node.selected ? DesignTokens.primary : colorScheme.outline;
      canvas.drawRRect(rrect, fill);
      canvas.drawRRect(rrect, border);

      final icon = nodeIconForType(node.type);
      final iconSize = 20.0 * viewport.zoom;
      final iconTop = rect.top + (rect.height - iconSize) / 2;
      _paintIcon(
        canvas,
        icon,
        Offset(rect.left + 12 * viewport.zoom, iconTop),
        iconSize,
        DesignTokens.primary,
      );

      final textLeft = rect.left + 40 * viewport.zoom;
      final textWidth = rect.width - 52 * viewport.zoom;
      _paintText(
        canvas,
        node.label.isEmpty ? node.type : node.label,
        Offset(textLeft, rect.top + (rect.height - 16 * viewport.zoom) / 2),
        textWidth,
        TextStyle(
          color: colorScheme.onSurface,
          fontSize: 13 * viewport.zoom,
          fontWeight: FontWeight.w600,
        ),
      );

      if (CanvasNodeType.generation.contains(node.type) &&
          node.prompt.isNotEmpty) {
        _paintText(
          canvas,
          node.prompt,
          Offset(textLeft, rect.bottom - 22 * viewport.zoom),
          textWidth,
          TextStyle(
            color: colorScheme.onSurfaceVariant,
            fontSize: 11 * viewport.zoom,
          ),
        );
      }
    }
  }

  void _paintIcon(
    Canvas canvas,
    IconData icon,
    Offset topLeft,
    double size,
    Color color,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(fontSize: size, fontFamily: icon.fontFamily, color: color),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, topLeft);
  }

  void _paintText(
    Canvas canvas,
    String text,
    Offset topLeft,
    double maxWidth,
    TextStyle style,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: "…",
    )..layout(maxWidth: maxWidth);
    painter.paint(canvas, topLeft);
  }

  void _paintConnection(Canvas canvas) {
    final draft = connection!;
    CanvasNode? source;
    for (final node in nodes) {
      if (node.id == draft.sourceId) {
        source = node;
        break;
      }
    }
    if (source == null) return;
    final p1 = canvasNodeOutputHandle(source, viewport);
    final p2 = draft.end;
    final dx = ((p2.dx - p1.dx).abs() * 0.5).clamp(24.0, 120.0);
    final paint = Paint()
      ..color = DesignTokens.primary
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..moveTo(p1.dx, p1.dy)
      ..cubicTo(p1.dx + dx, p1.dy, p2.dx - dx, p2.dy, p2.dx, p2.dy);
    canvas.drawPath(path, paint);
  }

  void _paintSelectionRect(Canvas canvas) {
    final rect = selectionRect!;
    canvas.drawRect(
      rect,
      Paint()..color = DesignTokens.primary.withValues(alpha: 0.12),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..color = DesignTokens.primary
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant CanvasPainter oldDelegate) {
    return oldDelegate.viewport.zoom != viewport.zoom ||
        oldDelegate.viewport.x != viewport.x ||
        oldDelegate.viewport.y != viewport.y ||
        oldDelegate.nodes != nodes ||
        oldDelegate.edges != edges ||
        oldDelegate.showEdges != showEdges ||
        oldDelegate.selectionRect != selectionRect ||
        oldDelegate.connection?.sourceId != connection?.sourceId ||
        oldDelegate.connection?.end != connection?.end;
  }
}
