import "dart:async";
import "dart:convert";
import "dart:math";

import "package:flutter/material.dart";
import "package:forui/forui.dart";

import "../../core/apiClient.dart";
import "../../shared/appLocalizations.dart";
import "agentApi.dart";
import "agentComposer.dart";
import "agentMentionSheet.dart";
import "agentMessageList.dart";
import "agentSkillSheet.dart";
import "agentTypes.dart";

/// 全屏 Agent 对话页。
///
/// ACT: 移动端没有桌面端 Dockview 的悬浮/停靠/拖拽/缩放能力，这里用全屏页代替。
class AgentPage extends StatefulWidget {
  final ApiClient client;
  final String directory;

  const AgentPage({super.key, required this.client, required this.directory});

  @override
  State<AgentPage> createState() => _AgentPageState();
}

class _AgentPageState extends State<AgentPage> {
  final Random _rng = Random();
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  late final AgentApi _api;

  List<AgentModel> _models = [];
  int _modelIndex = -1;

  List<AgentSession> _sessions = [];
  String? _currentSessionFile;
  String _currentSessionName = "";

  List<AgentMessage> _messages = [];

  bool _loading = true;
  bool _loadingMessages = false;

  bool _streaming = false;
  String? _currentRunId;
  StreamSubscription<String>? _subscription;
  AgentMessage? _streamingMessage;

  final List<AgentMention> _mentions = [];

  bool get _canSend =>
      !_streaming &&
      _modelIndex >= 0 &&
      _inputController.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _api = AgentApi(client: widget.client, directory: widget.directory);
    _inputController.addListener(_onInputChanged);
    _init();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onInputChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _init() async {
    await Future.wait([_loadModels(), _loadSessions()]);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadModels() async {
    try {
      final models = await _api.listModels();
      if (!mounted) return;
      setState(() {
        _models = models;
        if (models.isNotEmpty) _modelIndex = 0;
      });
    } catch (e) {
      if (!mounted) return;
      _showError(e.toString());
    }
  }

  Future<void> _loadSessions() async {
    try {
      final sessions = await _api.listSessions();
      if (!mounted) return;
      setState(() => _sessions = sessions);
    } catch (e) {
      if (!mounted) return;
      _showError(e.toString());
    }
  }

  Future<void> _refreshSessions() async {
    try {
      final sessions = await _api.listSessions();
      if (!mounted) return;
      setState(() {
        _sessions = sessions;
        final file = _currentSessionFile;
        if (file != null) {
          for (final session in sessions) {
            if (session.file == file) {
              _currentSessionName = session.name;
              break;
            }
          }
        }
      });
    } catch (_) {
      // 静默忽略刷新失败。
    }
  }

  Future<void> _switchSession(String file) async {
    if (_streaming) return;
    setState(() => _loadingMessages = true);
    try {
      final messages = await _api.getSession(file);
      if (!mounted) return;
      setState(() {
        _currentSessionFile = file;
        _messages = messages;
        _loadingMessages = false;
        _currentSessionName = _sessionNameFor(file);
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingMessages = false);
      _showError(e.toString());
    }
  }

  Future<void> _newConversation() async {
    if (_streaming) return;
    try {
      final session = await _api.createSession();
      if (!mounted) return;
      setState(() {
        _currentSessionFile = session.file;
        _currentSessionName = session.name;
        _messages = [];
      });
      await _refreshSessions();
    } catch (e) {
      if (!mounted) return;
      _showError(e.toString());
    }
  }

  Future<void> _rename(String file) async {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController(text: _sessionNameFor(file));
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.rename),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(l10n.confirm),
          ),
        ],
      ),
    );
    controller.dispose();
    if (newName == null || newName.isEmpty || !mounted) return;
    try {
      await _api.renameSession(file, newName);
      if (!mounted) return;
      if (file == _currentSessionFile) {
        setState(() => _currentSessionName = newName);
      }
      await _refreshSessions();
    } catch (e) {
      if (!mounted) return;
      _showError(e.toString());
    }
  }

  String _sessionNameFor(String file) {
    for (final session in _sessions) {
      if (session.file == file) return session.name;
    }
    return "";
  }

  void _selectModel(int index) {
    setState(() => _modelIndex = index);
  }

  Future<void> _send() async {
    final prompt = _inputController.text.trim();
    if (prompt.isEmpty || _streaming || _modelIndex < 0) return;
    final model = _models[_modelIndex];
    final runId = _newRunId();

    final mentionIds = RegExp(r"\{\{mention:([^}]+)\}\}")
        .allMatches(prompt)
        .map((m) => m.group(1))
        .whereType<String>()
        .toSet();
    final mentions = _mentions.where((m) => mentionIds.contains(m.id)).toList();

    final body = <String, dynamic>{
      "prompt": prompt,
      "directory": widget.directory,
      "providerId": model.providerId,
      "modelId": model.modelId,
      "runId": runId,
    };
    final sessionFile = _currentSessionFile;
    if (sessionFile != null) body["sessionFile"] = sessionFile;
    if (mentions.isNotEmpty) {
      body["mentions"] = mentions.map((m) => m.toJson()).toList();
    }

    final assistant = AgentMessage.assistant();
    setState(() {
      _messages.add(AgentMessage.user(prompt));
      _messages.add(assistant);
      _streamingMessage = assistant;
      _streaming = true;
      _currentRunId = runId;
      _inputController.clear();
      _mentions.clear();
    });
    _scrollToBottom();

    _subscription = widget.client
        .requestStream(
          "POST",
          "/api/agent",
          body: body,
          headers: _api.headers,
          contentType: "application/json",
        )
        .listen(
          (line) => _handleLine(line, assistant),
          onError: (Object e) => _handleStreamError(assistant, e),
          onDone: () => _finishStream(assistant),
          cancelOnError: false,
        );
  }

  void _handleLine(String line, AgentMessage assistant) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return;
    Map<String, dynamic> event;
    try {
      event = jsonDecode(trimmed) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    final type = event["type"] as String?;
    switch (type) {
      case "text":
      case "thinking":
        _appendPart(
          assistant,
          type!,
          event["blockId"] as String? ?? "",
          (event["delta"] as String?) ?? (event["content"] as String?) ?? "",
        );
        break;
      case "tool":
        _upsertTool(assistant, event["tool"]);
        break;
      case "error":
        assistant.error = event["message"] as String? ?? assistant.error;
        break;
      case "session":
        _handleSessionEvent(event);
        break;
      // done 事件在 onDone 统一收尾；其余事件（retry/compaction/…）本阶段忽略。
    }
    if (mounted) {
      setState(() {});
      if (type == "text" || type == "thinking") _scrollToBottom();
    }
  }

  void _appendPart(AgentMessage assistant, String type, String blockId, String delta) {
    if (delta.isEmpty) return;
    final parts = assistant.parts;
    for (int i = parts.length - 1; i >= 0; i--) {
      final part = parts[i];
      if (part.type == type && part.blockId == blockId) {
        part.content += delta;
        return;
      }
    }
    parts.add(type == "thinking"
        ? AgentPart.thinking(blockId: blockId, content: delta)
        : AgentPart.text(blockId: blockId, content: delta));
  }

  void _upsertTool(AgentMessage assistant, dynamic toolJson) {
    if (toolJson is! Map) return;
    final tool = AgentTool.fromJson(Map<String, dynamic>.from(toolJson));
    final parts = assistant.parts;
    for (int i = parts.length - 1; i >= 0; i--) {
      final part = parts[i];
      if (part.type == "tool" && part.blockId == tool.id) {
        part.tool = tool;
        return;
      }
    }
    parts.add(AgentPart.tool(tool));
  }

  void _handleSessionEvent(Map<String, dynamic> event) {
    final file = event["file"] as String?;
    if (file != null && file.isNotEmpty && _currentSessionFile == null) {
      _currentSessionFile = file;
    }
  }

  void _handleStreamError(AgentMessage assistant, Object error) {
    if (assistant.error == null || assistant.error!.isEmpty) {
      assistant.error = error is ApiException ? error.message : error.toString();
    }
    _completeStream(assistant);
  }

  void _finishStream(AgentMessage assistant) {
    _completeStream(assistant);
  }

  void _completeStream(AgentMessage assistant) {
    if (!_streaming) return;
    assistant.streaming = false;
    _streaming = false;
    _currentRunId = null;
    _subscription = null;
    if (mounted) setState(() {});
    _refreshSessions();
  }

  Future<void> _stop() async {
    final subscription = _subscription;
    final runId = _currentRunId;
    if (subscription != null) {
      _subscription = null;
      await subscription.cancel();
    }
    if (runId != null) {
      try {
        await _api.stopRuns([runId]);
      } catch (_) {
        // 停止请求失败不阻塞本地收尾。
      }
    }
    final assistant = _streamingMessage;
    if (assistant != null && assistant.parts.isEmpty && assistant.content.isEmpty) {
      _messages.remove(assistant);
    }
    setState(() {
      _streaming = false;
      _currentRunId = null;
      _streamingMessage = null;
    });
    _refreshSessions();
  }

  Future<void> _openSkills() async {
    try {
      final skills = await _api.listSkills();
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        builder: (context) => AgentSkillSheet(skills: skills, onSelect: _insertSkill),
      );
    } catch (e) {
      if (!mounted) return;
      _showError(e.toString());
    }
  }

  void _insertSkill(AgentSkill skill) {
    final token = skill.displayName.isEmpty ? skill.name : skill.displayName;
    _insertText(token);
  }

  Future<void> _openMention() async {
    final mention = await showModalBottomSheet<AgentMention>(
      context: context,
      isScrollControlled: true,
      builder: (context) => AgentMentionSheet(api: _api),
    );
    if (mention == null || !mounted) return;
    setState(() => _mentions.add(mention));
    _insertText("{{mention:${mention.id}}}");
  }

  void _insertText(String token) {
    final text = _inputController.text;
    final selection = _inputController.selection;
    final insertAt = selection.isValid ? selection.start : text.length;
    final updated = text.substring(0, insertAt) + token + text.substring(insertAt);
    _inputController.value = TextEditingValue(
      text: updated,
      selection: TextSelection.collapsed(offset: insertAt + token.length),
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  String _newRunId() {
    final bytes = List<int>.generate(16, (_) => _rng.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, "0")).join();
    return "${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}";
  }

  void _showError(String message) {
    if (!mounted) return;
    showFToast(
      context: context,
      variant: .destructive,
      title: Text(message),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final noModel = !_loading && _models.isEmpty;
    return FScaffold(
      header: FHeader(
        title: Text(_currentSessionName.isEmpty ? l10n.agent : _currentSessionName),
        suffixes: [
          _buildModelSelector(l10n),
          FHeaderAction(
            icon: const Icon(FLucideIcons.history),
            semanticsTooltip: l10n.conversation,
            onPress: _openSessions,
          ),
        ],
      ),
      childPad: false,
      child: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: FCircularProgress())
                : _loadingMessages
                    ? const Center(child: FCircularProgress())
                    : AgentMessageList(
                        messages: _messages,
                        scrollController: _scrollController,
                      ),
          ),
          AgentComposer(
            controller: _inputController,
            canSend: _canSend,
            streaming: _streaming,
            noModel: noModel,
            onSend: _send,
            onStop: _stop,
            onSkills: _openSkills,
            onMention: _openMention,
          ),
        ],
      ),
    );
  }

  Widget _buildModelSelector(AppLocalizations l10n) {
    if (_models.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 8),
        child: Icon(FLucideIcons.brain),
      );
    }
    final current = _modelIndex >= 0 ? _models[_modelIndex] : null;
    return Material(
      type: MaterialType.transparency,
      child: PopupMenuButton<int>(
        tooltip: l10n.model,
        onSelected: _selectModel,
        itemBuilder: (context) => [
          for (int i = 0; i < _models.length; i++)
            PopupMenuItem<int>(
              value: i,
              child: Row(
                children: [
                  SizedBox(
                    width: 18,
                    child: i == _modelIndex ? const Icon(FLucideIcons.check, size: 18) : null,
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_models[i].displayLabel)),
                ],
              ),
            ),
        ],
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(FLucideIcons.brain),
              const SizedBox(width: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 120),
                child: Text(
                  current?.label ?? l10n.model,
                  overflow: TextOverflow.ellipsis,
                  style: context.theme.typography.body.md,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openSessions() {
    showFSheet(
      context: context,
      side: FLayout.rtl,
      builder: (context) => _buildSessionsSheet(AppLocalizations.of(context)),
    );
  }

  Widget _buildSessionsSheet(AppLocalizations l10n) {
    return SafeArea(
      child: Column(
        children: [
          FTile(
            title: Text(l10n.conversation),
            suffix: FButton(
              onPress: () {
                Navigator.pop(context);
                _newConversation();
              },
              variant: .ghost,
              prefix: const Icon(FLucideIcons.plus),
              child: Text(l10n.newConversation),
            ),
          ),
          FDivider(style: .delta(padding: .value(EdgeInsets.zero))),
          Expanded(
            child: _sessions.isEmpty
                ? Center(child: Text(l10n.noConversation))
                : ListView.builder(
                    itemCount: _sessions.length,
                    itemBuilder: (context, index) {
                      final session = _sessions[index];
                      final selected = session.file == _currentSessionFile;
                      return FTile(
                        selected: selected,
                        title: Text(
                          session.name.isEmpty ? session.file : session.name,
                        ),
                        suffix: FButton.icon(
                          onPress: () {
                            Navigator.pop(context);
                            _rename(session.file);
                          },
                          variant: .ghost,
                          semanticsTooltip: l10n.rename,
                          child: const Icon(FLucideIcons.pencil),
                        ),
                        onPress: () {
                          Navigator.pop(context);
                          _switchSession(session.file);
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
