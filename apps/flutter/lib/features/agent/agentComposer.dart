import "package:flutter/material.dart";
import "package:forui/forui.dart";

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
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (noModel)
            Container(
              width: double.infinity,
              color: context.theme.colors.error,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Text(
                l10n.noModel,
                style: TextStyle(color: context.theme.colors.errorForeground),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                FButton.icon(
                  onPress: onSkills,
                  variant: .ghost,
                  semanticsTooltip: l10n.skills,
                  child: const Icon(FLucideIcons.sparkles),
                ),
                FButton.icon(
                  onPress: onMention,
                  variant: .ghost,
                  semanticsTooltip: l10n.mention,
                  child: const Icon(FLucideIcons.paperclip),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: FTextField(
                    control: FTextFieldControl.managed(controller: controller),
                    hint: l10n.inputPlaceholder,
                    minLines: 1,
                    maxLines: 5,
                    textInputAction: TextInputAction.newline,
                  ),
                ),
                const SizedBox(width: 8),
                FButton.icon(
                  onPress: streaming
                      ? onStop
                      : (canSend ? onSend : null),
                  variant: .primary,
                  semanticsTooltip: streaming ? l10n.stop : l10n.send,
                  child: Icon(streaming ? FLucideIcons.square : FLucideIcons.send),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
