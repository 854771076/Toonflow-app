import "package:flutter/material.dart";

import "../../shared/appLocalizations.dart";
import "agentTypes.dart";

/// Agent 消息列表：渲染用户/助手气泡、思考块与工具徽标。
class AgentMessageList extends StatelessWidget {
  final List<AgentMessage> messages;
  final ScrollController scrollController;

  const AgentMessageList({
    super.key,
    required this.messages,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (messages.isEmpty) {
      return Center(
        child: Text(
          l10n.noConversation,
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      );
    }
    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.all(12),
      itemCount: messages.length,
      itemBuilder: (context, index) => _MessageBubble(
        message: messages[index],
        l10n: l10n,
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final AgentMessage message;
  final AppLocalizations l10n;

  const _MessageBubble({required this.message, required this.l10n});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.82,
        ),
        decoration: BoxDecoration(
          color: message.isUser ? scheme.primaryContainer : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: message.isUser
            ? Text(message.content)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: _assistantChildren(context),
              ),
      ),
    );
  }

  List<Widget> _assistantChildren(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final children = <Widget>[];
    for (final part in message.parts) {
      if (part.type == "tool") {
        children.add(_ToolBadge(tool: part.tool!));
      } else if (part.type == "thinking") {
        children.add(_ThinkingBlock(part: part, l10n: l10n));
      } else if (part.content.isNotEmpty) {
        children.add(SelectableText(part.content));
      }
    }
    final error = message.error;
    if (error != null && error.isNotEmpty) {
      children.add(Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(error, style: TextStyle(color: scheme.error)),
      ));
    }
    if (message.parts.isEmpty) {
      if (message.content.isNotEmpty) {
        children.add(SelectableText(message.content));
      } else if (message.streaming) {
        children.add(Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 8),
            Text(l10n.thinking, style: TextStyle(color: scheme.onSurfaceVariant)),
          ],
        ));
      }
    }
    return children;
  }
}

class _ThinkingBlock extends StatefulWidget {
  final AgentPart part;
  final AppLocalizations l10n;

  const _ThinkingBlock({required this.part, required this.l10n});

  @override
  State<_ThinkingBlock> createState() => _ThinkingBlockState();
}

class _ThinkingBlockState extends State<_ThinkingBlock> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = TextStyle(color: scheme.onSurfaceVariant, fontSize: 13);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _expanded ? Icons.expand_more : Icons.chevron_right,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Icon(Icons.psychology_outlined, size: 16, color: scheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(widget.l10n.thinking, style: muted),
              ],
            ),
          ),
        ),
        if (_expanded && widget.part.content.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(widget.part.content, style: muted),
          ),
      ],
    );
  }
}

class _ToolBadge extends StatelessWidget {
  final AgentTool tool;

  const _ToolBadge({required this.tool});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (color, label) = _toolStatus(tool.status);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.handyman_outlined, size: 16, color: scheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              tool.name,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              label,
              style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  (Color, String) _toolStatus(String status) {
    switch (status) {
      case "success":
        return (Colors.green, "success");
      case "error":
        return (Colors.red, "error");
      case "interrupted":
        return (Colors.grey, "interrupted");
      default:
        return (Colors.blue, "running");
    }
  }
}
