import "package:flutter/material.dart";
import "package:forui/forui.dart";

import "../../shared/appLocalizations.dart";

/// 基础 Markdown 文本编辑器：在光标处插入/包裹语法，保存写入工作区。
class TextEditor extends StatefulWidget {
  final String initialText;
  final ValueChanged<String> onChanged;
  final Future<void> Function() onSave;

  const TextEditor({
    super.key,
    required this.initialText,
    required this.onChanged,
    required this.onSave,
  });

  @override
  State<TextEditor> createState() => _TextEditorState();
}

class _TextEditorState extends State<TextEditor> {
  late final TextEditingController _controller;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _notifyChanged() => widget.onChanged(_controller.text);

  void _surround(String before, String after) {
    final value = _controller.value;
    if (!value.selection.isValid) {
      final offset = value.text.length;
      _controller.text = value.text + before + after;
      _controller.selection = TextSelection.collapsed(
        offset: offset + before.length,
      );
    } else {
      final start = value.selection.start;
      final end = value.selection.end;
      final selected = value.text.substring(start, end);
      _controller.value = TextEditingValue(
        text: value.text.replaceRange(start, end, before + selected + after),
        selection: TextSelection(
          baseOffset: start + before.length,
          extentOffset: start + before.length + selected.length,
        ),
      );
    }
    _notifyChanged();
  }

  void _insertLinePrefix(String prefix) {
    final value = _controller.value;
    final text = value.text;
    final start = value.selection.start;
    final searchEnd = start > 0 ? start - 1 : 0;
    final lineBreak = text.lastIndexOf("\n", searchEnd);
    final lineStart = lineBreak < 0 ? 0 : lineBreak + 1;
    _controller.value = TextEditingValue(
      text: text.replaceRange(lineStart, lineStart, prefix),
      selection: TextSelection.collapsed(offset: start + prefix.length),
    );
    _notifyChanged();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.onSave();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      children: [
        _buildToolbar(l10n),
        const FDivider(),
        Expanded(
          child: FTextField(
            control: FTextFieldControl.managed(
              controller: _controller,
              onChange: (_) => _notifyChanged(),
            ),
            maxLines: null,
            expands: true,
            keyboardType: TextInputType.multiline,
            textAlignVertical: TextAlignVertical.top,
          ),
        ),
      ],
    );
  }

  Widget _buildToolbar(AppLocalizations l10n) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          FButton.icon(
            variant: .ghost,
            size: .sm,
            semanticsTooltip: "Bold",
            onPress: () => _surround("**", "**"),
            child: const Icon(FLucideIcons.bold),
          ),
          FButton.icon(
            variant: .ghost,
            size: .sm,
            semanticsTooltip: "Italic",
            onPress: () => _surround("*", "*"),
            child: const Icon(FLucideIcons.italic),
          ),
          FButton.icon(
            variant: .ghost,
            size: .sm,
            semanticsTooltip: "Heading",
            onPress: () => _insertLinePrefix("# "),
            child: const Icon(FLucideIcons.heading),
          ),
          FButton.icon(
            variant: .ghost,
            size: .sm,
            semanticsTooltip: "Bulleted list",
            onPress: () => _insertLinePrefix("- "),
            child: const Icon(FLucideIcons.list),
          ),
          FButton.icon(
            variant: .ghost,
            size: .sm,
            semanticsTooltip: l10n.save,
            onPress: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(FLucideIcons.save),
          ),
        ],
      ),
    );
  }
}
