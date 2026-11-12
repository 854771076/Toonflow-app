import "package:flutter/material.dart";

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
            child: Text(l10n.skills, style: Theme.of(context).textTheme.titleMedium),
          ),
          const Divider(height: 1),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: skills.length,
              itemBuilder: (context, index) {
                final skill = skills[index];
                return ListTile(
                  leading: const Icon(Icons.auto_awesome_outlined),
                  title: Text(skill.displayName.isEmpty ? skill.name : skill.displayName),
                  subtitle: skill.description.isEmpty ? null : Text(skill.description),
                  onTap: () {
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
