import "package:flutter/material.dart";
import "package:forui/forui.dart";

import "../../shared/appLocalizations.dart";
import "agentTypes.dart";

/// 技能菜单弹窗：列出技能名称与描述，点击回传选中的技能。
class AgentSkillSheet extends StatelessWidget {
  final List<AgentSkill> skills;
  final ValueChanged<AgentSkill> onSelect;

  const AgentSkillSheet({super.key, required this.skills, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(l10n.skills, style: context.theme.typography.display.lg),
          ),
          FDivider(style: .delta(padding: .value(EdgeInsets.zero))),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: skills.length,
              itemBuilder: (context, index) {
                final skill = skills[index];
                return FTile(
                  prefix: const Icon(FLucideIcons.sparkles),
                  title: Text(skill.displayName.isEmpty ? skill.name : skill.displayName),
                  subtitle: skill.description.isEmpty ? null : Text(skill.description),
                  onPress: () {
                    Navigator.pop(context);
                    onSelect(skill);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
