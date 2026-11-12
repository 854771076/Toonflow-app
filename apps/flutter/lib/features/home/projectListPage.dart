import "package:flutter/material.dart";

import "../../core/apiClient.dart";
import "../../core/authService.dart";
import "../../core/projectStore.dart";
import "../../shared/appLocalizations.dart";
import "../assets/assetLibraryPage.dart";
import "../canvas/canvasPage.dart";
import "../settings/settingsPage.dart";

/// 项目列表页：展示本地保存的项目，支持添加项目（选择工作区目录）。
class ProjectListPage extends StatefulWidget {
  final ApiClient client;
  final AuthService auth;
  final Future<void> Function() onLoggedOut;
  final VoidCallback onToggleLanguage;
  final void Function(String code)? onLocaleChanged;
  final void Function(String mode)? onThemeModeChanged;

  const ProjectListPage({
    super.key,
    required this.client,
    required this.auth,
    required this.onLoggedOut,
    required this.onToggleLanguage,
    this.onLocaleChanged,
    this.onThemeModeChanged,
  });

  @override
  State<ProjectListPage> createState() => _ProjectListPageState();
}

class _ProjectListPageState extends State<ProjectListPage> {
  List<Project> _projects = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final projects = await ProjectStore.load();
    projects.sort((a, b) => b.lastOpenedAt.compareTo(a.lastOpenedAt));
    if (mounted) setState(() => _projects = projects);
  }

  Future<void> _addProject() async {
    final l10n = AppLocalizations.of(context);
    final picked = await Navigator.of(context).push<Map<String, String>>(
      MaterialPageRoute(
        builder: (_) => DirectoryPickerPage(client: widget.client),
      ),
    );
    if (picked == null) return;
    if (!mounted) return;

    final nameController = TextEditingController(text: picked["name"]);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.projectName),
        content: TextField(controller: nameController, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, nameController.text.trim()),
            child: Text(l10n.confirm),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;

    final project = Project(
      directory: picked["directory"]!,
      name: name,
      lastOpenedAt: DateTime.now(),
    );
    final updated = [
      project,
      ..._projects.where((p) => p.directory != project.directory),
    ];
    setState(() => _projects = updated);
    await ProjectStore.save(updated);
  }

  Future<void> _openProject(Project project) async {
    project = Project(
      directory: project.directory,
      name: project.name,
      lastOpenedAt: DateTime.now(),
    );
    final updated = [
      project,
      ..._projects.where((p) => p.directory != project.directory),
    ];
    setState(() => _projects = updated);
    await ProjectStore.save(updated);

    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CanvasPage(
          client: widget.client,
          directory: project.directory,
          title: project.name,
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

  Future<void> _logout() async {
    await widget.auth.logout();
    await widget.onLoggedOut();
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SettingsPage(
          client: widget.client,
          onLocaleChanged: widget.onLocaleChanged,
          onThemeModeChanged: widget.onThemeModeChanged,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.projects),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: _openSettings,
            tooltip: l10n.settings,
          ),
          IconButton(
            icon: const Icon(Icons.photo_library_outlined),
            onPressed: _openAssetLibrary,
            tooltip: l10n.assetLibrary,
          ),
          IconButton(
            icon: const Icon(Icons.translate),
            onPressed: widget.onToggleLanguage,
            tooltip: l10n.switchLanguage,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _logout,
            tooltip: l10n.logout,
          ),
        ],
      ),
      body: _projects.isEmpty
          ? Center(child: Text(l10n.noProjects))
          : ListView.separated(
              itemCount: _projects.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final project = _projects[index];
                return ListTile(
                  leading: const Icon(Icons.folder),
                  title: Text(project.name),
                  subtitle: Text(project.directory),
                  onTap: () => _openProject(project),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addProject,
        tooltip: l10n.addProject,
        child: const Icon(Icons.add),
      ),
    );
  }
}

/// 目录选择器：浏览服务端工作区目录，选择后返回 { name, directory }。
class DirectoryPickerPage extends StatefulWidget {
  final ApiClient client;

  const DirectoryPickerPage({super.key, required this.client});

  @override
  State<DirectoryPickerPage> createState() => _DirectoryPickerPageState();
}

class _DirectoryPickerPageState extends State<DirectoryPickerPage> {
  String _path = "";
  String? _absolutePath;
  String? _parent;
  List<Map<String, String>> _directories = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.client
          .getData("/api/workspaces/list", query: {"path": _path}) as Map<String, dynamic>;
      final dirs = (data["directories"] as List)
          .map((e) => Map<String, String>.from(e as Map))
          .toList();
      setState(() {
        _absolutePath = data["absolutePath"] as String?;
        _parent = data["parent"] as String?;
        _directories = dirs;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _enter(String path) async {
    _path = path;
    await _load();
  }

  Future<void> _useCurrent() async {
    if (_absolutePath == null) return;
    try {
      final data = await widget.client
          .getData("/api/workspaces/check", query: {"directory": _absolutePath}) as Map<String, dynamic>;
      final directory = data["directory"] as String? ?? _absolutePath!;
      final name = directory.split(RegExp(r"[/\\]")).where((s) => s.isNotEmpty).last;
      if (!mounted) return;
      Navigator.of(context).pop({"name": name, "directory": directory});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.selectDirectory)),
      body: Column(
        children: [
          if (_absolutePath != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                "${l10n.currentDirectory}: $_absolutePath",
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(_error!),
                            const SizedBox(height: 8),
                            OutlinedButton(
                              onPressed: _load,
                              child: Text(l10n.retry),
                            ),
                          ],
                        ),
                      )
                    : ListView(
                        children: [
                          if (_parent != null)
                            ListTile(
                              leading: const Icon(Icons.arrow_upward),
                              title: Text(l10n.parentDirectory),
                              onTap: () => _enter(_parent!),
                            ),
                          ..._directories.map(
                            (dir) => ListTile(
                              leading: const Icon(Icons.folder),
                              title: Text(dir["name"] ?? ""),
                              onTap: () => _enter(dir["path"] ?? ""),
                            ),
                          ),
                        ],
                      ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton(
            onPressed: _absolutePath == null ? null : _useCurrent,
            child: Text(l10n.useThisDirectory),
          ),
        ),
      ),
    );
  }
}
