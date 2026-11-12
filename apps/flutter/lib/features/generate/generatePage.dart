import "dart:async";
import "dart:math";
import "dart:typed_data";

import "package:flutter/material.dart";

import "../../core/apiClient.dart";
import "../../shared/appLocalizations.dart";

/// 媒体模型（对应 `/api/ai/media/models` 返回项）。
class MediaModel {
  final String providerId;
  final String providerLabel;
  final String modelId;
  final String label;
  final String type;

  MediaModel({
    required this.providerId,
    required this.providerLabel,
    required this.modelId,
    required this.label,
    required this.type,
  });

  static MediaModel fromJson(Map<String, dynamic> json) => MediaModel(
        providerId: json["providerId"] as String? ?? "",
        providerLabel: json["providerLabel"] as String? ?? "",
        modelId: json["modelId"] as String? ?? "",
        label: json["label"] as String? ?? "",
        type: json["type"] as String? ?? "image",
      );
}

/// 生成页：选择模型、输入提示词，触发图片生成并轮询展示结果。
class GeneratePage extends StatefulWidget {
  final ApiClient client;
  final String directory;

  const GeneratePage({
    super.key,
    required this.client,
    required this.directory,
  });

  @override
  State<GeneratePage> createState() => _GeneratePageState();
}

class _GeneratePageState extends State<GeneratePage> {
  final TextEditingController _promptController = TextEditingController();
  final TextEditingController _providerController = TextEditingController();
  final TextEditingController _modelController = TextEditingController();
  final TextEditingController _referenceImagesController = TextEditingController();
  final TextEditingController _ratioController = TextEditingController();
  final TextEditingController _resolutionController = TextEditingController();
  final TextEditingController _durationController = TextEditingController();
  final TextEditingController _voiceController = TextEditingController();

  String _mediaType = "image";
  List<MediaModel> _models = [];
  MediaModel? _selected;
  bool _loadingModels = true;
  bool _generating = false;
  String _status = "";
  Uint8List? _resultImage;
  String? _resultPath;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadModels();
  }

  @override
  void dispose() {
    _promptController.dispose();
    _providerController.dispose();
    _modelController.dispose();
    _referenceImagesController.dispose();
    _ratioController.dispose();
    _resolutionController.dispose();
    _durationController.dispose();
    _voiceController.dispose();
    super.dispose();
  }

  Future<void> _loadModels() async {
    setState(() {
      _loadingModels = true;
      _error = null;
    });
    try {
      final data = await widget.client.getData("/api/ai/media/models") as List;
      final models = data
          .map((e) => MediaModel.fromJson(Map<String, dynamic>.from(e as Map)))
          .where((m) => m.type == _mediaType)
          .toList();
      if (!mounted) return;
      setState(() {
        _models = models;
        _selected = models.isNotEmpty ? models.first : null;
        _loadingModels = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loadingModels = false;
      });
    }
  }

  void _switchMediaType(String mediaType) {
    if (_mediaType == mediaType) return;
    setState(() {
      _mediaType = mediaType;
      _models = [];
      _selected = null;
      _resultImage = null;
      _resultPath = null;
      _status = "";
      _error = null;
    });
    _loadModels();
  }

  Future<void> _generate() async {
    final l10n = AppLocalizations.of(context);
    final prompt = _promptController.text.trim();
    final providerId = _selected?.providerId ?? _providerController.text.trim();
    final modelId = _selected?.modelId ?? _modelController.text.trim();
    if (prompt.isEmpty || providerId.isEmpty || modelId.isEmpty) return;

    setState(() {
      _generating = true;
      _error = null;
      _resultImage = null;
      _resultPath = null;
      _status = l10n.generating;
    });

    final taskId = _newTaskId();
    final body = <String, dynamic>{
      "directory": widget.directory,
      "mediaType": _mediaType,
      "taskId": taskId,
      "providerId": providerId,
      "modelId": modelId,
      "prompt": prompt,
    };
    if (_mediaType == "image") {
      final images = _parseReferenceImages();
      if (images.isNotEmpty) body["images"] = images;
    } else if (_mediaType == "video") {
      _putIfNotEmpty(body, "ratio", _ratioController.text);
      _putIfNotEmpty(body, "resolution", _resolutionController.text);
      final duration = double.tryParse(_durationController.text.trim());
      if (duration != null && duration > 0 && duration <= 3600) {
        body["duration"] = duration;
      }
    } else if (_mediaType == "audio") {
      _putIfNotEmpty(body, "voice", _voiceController.text);
    }

    try {
      await widget.client.postData("/api/ai/media/generate", body: body);

      final path = await _poll(taskId);
      if (path != null) {
        if (_mediaType == "image") {
          await _loadResult(path);
        } else {
          if (!mounted) return;
          setState(() {
            _resultPath = path;
            _status = l10n.generated;
          });
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _status = l10n.generateFailed;
      });
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  List<Map<String, String>> _parseReferenceImages() {
    final text = _referenceImagesController.text;
    if (text.trim().isEmpty) return [];
    final result = <Map<String, String>>[];
    for (final raw in text.split(RegExp(r"[\n,，]"))) {
      final path = raw.trim();
      if (path.isEmpty) continue;
      result.add({"path": path, "mimeType": _mimeTypeFor(path)});
    }
    return result;
  }

  String _mimeTypeFor(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith(".png")) return "image/png";
    if (lower.endsWith(".jpg") || lower.endsWith(".jpeg")) return "image/jpeg";
    if (lower.endsWith(".webp")) return "image/webp";
    if (lower.endsWith(".gif")) return "image/gif";
    if (lower.endsWith(".bmp")) return "image/bmp";
    return "image/png";
  }

  void _putIfNotEmpty(Map<String, dynamic> body, String key, String value) {
    final trimmed = value.trim();
    if (trimmed.isNotEmpty) body[key] = trimmed;
  }

  Future<String?> _poll(String taskId) async {
    final l10n = AppLocalizations.of(context);
    for (int i = 0; i < 150; i++) {
      await Future.delayed(const Duration(seconds: 2));
      final tasks = await widget.client.postData("/api/ai/media/tasks/status", body: {
        "directory": widget.directory,
        "taskIds": [taskId],
      }) as List;
      if (tasks.isEmpty) continue;
      final task = Map<String, dynamic>.from(tasks.first as Map);
      final state = task["state"] as String? ?? "";
      if (mounted) setState(() => _status = state);
      if (state == "succeeded") {
        final result = task["result"];
        if (result is Map) {
          final data = result["data"] as List? ?? [];
          if (data.isNotEmpty) {
            return Map<String, dynamic>.from(data.first as Map)["path"] as String?;
          }
        }
        return null;
      }
      if (state == "failed" || state == "cancelled" || state == "interrupted") {
        final result = task["result"];
        final message = result is Map ? result["message"]?.toString() : null;
        throw Exception(message ?? l10n.generateFailed);
      }
    }
    throw Exception("生成超时");
  }

  Future<void> _loadResult(String path) async {
    final l10n = AppLocalizations.of(context);
    try {
      final bytes =
          await widget.client.getBytes("/api/assets/read", query: {"path": path});
      if (!mounted) return;
      setState(() {
        _resultImage = bytes;
        _status = l10n.generated;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = "${l10n.generated}: $e");
    }
  }

  String _newTaskId() {
    final rng = Random.secure();
    final bytes = Uint8List(16);
    for (int i = 0; i < bytes.length; i++) {
      bytes[i] = rng.nextInt(256);
    }
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 10xx
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, "0")).join();
    return "${hex.substring(0, 8)}-${hex.substring(8, 12)}-"
        "${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}";
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.generate)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<String>(
            segments: [
              ButtonSegment(value: "image", label: Text(l10n.nodeTypeImage)),
              ButtonSegment(value: "video", label: Text(l10n.nodeTypeVideo)),
              ButtonSegment(value: "audio", label: Text(l10n.nodeTypeAudio)),
            ],
            selected: {_mediaType},
            onSelectionChanged: _generating
                ? null
                : (selection) => _switchMediaType(selection.first),
          ),
          const SizedBox(height: 16),
          if (_loadingModels)
            const LinearProgressIndicator()
          else if (_models.isNotEmpty)
            DropdownButtonFormField<MediaModel>(
              initialValue: _selected,
              decoration: InputDecoration(
                labelText: l10n.modelId,
                border: const OutlineInputBorder(),
              ),
              items: _models
                  .map((m) => DropdownMenuItem(
                        value: m,
                        child: Text("${m.providerLabel} / ${m.label}"),
                      ))
                  .toList(),
              onChanged: _generating
                  ? null
                  : (value) => setState(() => _selected = value),
            )
          else ...[
            TextField(
              controller: _providerController,
              decoration: InputDecoration(
                labelText: l10n.providerId,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _modelController,
              decoration: InputDecoration(
                labelText: l10n.modelId,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
          const SizedBox(height: 12),
          if (_mediaType == "image") ...[
            TextField(
              controller: _referenceImagesController,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: l10n.referenceImages,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (_mediaType == "video") ...[
            TextField(
              controller: _ratioController,
              decoration: InputDecoration(
                labelText: l10n.ratio,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _resolutionController,
              decoration: InputDecoration(
                labelText: l10n.resolution,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _durationController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: l10n.duration,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (_mediaType == "audio") ...[
            TextField(
              controller: _voiceController,
              decoration: InputDecoration(
                labelText: l10n.voice,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _promptController,
            minLines: 2,
            maxLines: 5,
            decoration: InputDecoration(
              labelText: l10n.prompt,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _generating ? null : _generate,
            icon: const Icon(Icons.auto_awesome),
            label: Text(l10n.startGenerate),
          ),
          const SizedBox(height: 20),
          if (_status.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  if (_generating)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_status)),
                ],
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
          if (_mediaType == "image" && _resultImage != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(_resultImage!),
            ),
          // ACT: 视频/音频结果仅展示工作区相对路径与状态文案，不内置播放器，
          // 避免引入播放依赖；后续如需播放可在此接入 video_player/audioplayers。
          if (_mediaType != "image" && _resultPath != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.generatedResult),
                  const SizedBox(height: 4),
                  SelectableText(_resultPath!),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
