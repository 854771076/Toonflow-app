import "package:flutter/material.dart";

import "../../shared/appLocalizations.dart";

/// Agent 底部输入区：输入框 + 发送/停止 + 技能菜单 + 提及按钮。
class AgentComposer extends StatelessWidget {
  final TextEditingController controller;
  final bool canSend;
  final bool streaming;
  final bool noModel;
  final VoidCallback onSend;
  final VoidCallback onStop;
  final VoidCallback onSkills;
  final VoidCallback onMention;

  const AgentComposer({
    super.key,
    required this.controller,
    required this.canSend,
    required this.streaming,
    required this.noModel,
    required this.onSend,
    required this.onStop,
    required this.onSkills,
    required this.onMention,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (noModel)
            Container(
              width: double.infinity,
              color: scheme.errorContainer,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Text(
                l10n.noModel,
                style: TextStyle(color: scheme.onErrorContainer, fontSize: 13),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  icon: const Icon(Icons.auto_awesome_outlined),
                  tooltip: l10n.skills,
                  onPressed: onSkills,
                ),
                IconButton(
                  icon: const Icon(Icons.attach_file_outlined),
                  tooltip: l10n.mention,
                  onPressed: onMention,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: TextField(
                    controller: controller,
                    minLines: 1,
                    maxLines: 5,
                    textInputAction: TextInputAction.newline,
                    decoration: InputDecoration(
                      hintText: l10n.inputPlaceholder,
                      isDense: true,
                      filled: true,
                      fillColor: scheme.surfaceContainerHighest,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  icon: Icon(streaming ? Icons.stop : Icons.send),
                  tooltip: streaming ? l10n.stop : l10n.send,
                  onPressed: streaming
                      ? onStop
                      : (canSend ? onSend : null),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
