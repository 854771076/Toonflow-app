import "dart:typed_data";

import "package:flutter/material.dart";
import "package:forui/forui.dart";
import "package:share_plus/share_plus.dart";

import "../../core/apiClient.dart";
import "../../core/authService.dart";
import "../../core/projectStore.dart";
import "../../core/workspaceFiles.dart";
import "../../shared/appLocalizations.dart";
import "../../shared/designTokens.dart";
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
  final Map<String, Uint8List?> _covers = {};
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _projectsKey = GlobalKey();
  bool _projectTypeLocal = true;
  String? _username;

  @override
  void initState() {
    super.initState();
    _load();
    _loadSession();
  }

  Future<void> _loadSession() async {
    try {
      final session = await widget.auth.session();
      if (mounted && session.authenticated) {
        setState(() => _username = session.username ?? session.sub);
      }
    } catch (_) {
      // 会话读取失败不影响首页展示。
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final projects = await ProjectStore.load();
    projects.sort((a, b) => b.lastOpenedAt.compareTo(a.lastOpenedAt));
    if (mounted) setState(() => _projects = projects);
    _loadCovers(projects);
  }

  Future<void> _loadCovers(List<Project> projects) async {
    for (final project in projects) {
      if (!_covers.containsKey(project.directory)) _loadCover(project.directory);
    }
  }

  Future<void> _loadCover(String directory) async {
    final bytes = await _findCoverImage(directory);
    if (mounted) setState(() => _covers[directory] = bytes);
  }

  Future<Uint8List?> _findCoverImage(String directory) async {
    try {
      final files = WorkspaceFiles(client: widget.client, directory: directory);
      final data = await files.list("assets");
      final entries = data["entries"] as List;
      for (final e in entries) {
        final entry = Map<String, dynamic>.from(e as Map);
        if (entry["type"] != "file") continue;
        final name = entry["name"] as String? ?? "";
        if (_isImage(name)) {
          return await files.readBytes(entry["path"] as String);
        }
      }
    } catch (_) {
      // 封面加载失败时回退为文件夹图标，不阻塞列表。
    }
    return null;
  }

  bool _isImage(String name) {
    final lower = name.toLowerCase();
    return lower.endsWith(".png") ||
        lower.endsWith(".jpg") ||
        lower.endsWith(".jpeg") ||
        lower.endsWith(".gif") ||
        lower.endsWith(".webp") ||
        lower.endsWith(".bmp");
  }

  Future<void> _addProject() async {
    final directory = await showFDialog<String>(
      context: context,
      builder: (context, style, animation) => FDialog(
        animation: animation,
        builder: (context, style) => DirectoryPickerPage(client: widget.client),
      ),
    );
    if (directory == null || directory.isEmpty) return;
    if (!mounted) return;

    // 对齐 web createProject：拿到服务端规范化目录，空目录写入初始画布后直接进入。
    final listing = await WorkspaceFiles(client: widget.client, directory: directory)
        .list("");
    final resolvedDirectory = listing["directory"] as String? ?? directory;
    if (listing["empty"] == true) {
      await WorkspaceFiles(client: widget.client, directory: resolvedDirectory).writeJson(
        "画布1.json",
        {
          "toonflowCanvas": true,
          "nodes": <dynamic>[],
          "edges": <dynamic>[],
          "viewport": {"x": 0, "y": 0, "zoom": 1},
        },
        exclusive: true,
      );
    }

    final name = resolvedDirectory
        .split(RegExp(r"[/\\]"))
        .where((s) => s.isNotEmpty)
        .last;
    if (!mounted) return;
    await _openProject(
      Project(directory: resolvedDirectory, name: name, lastOpenedAt: DateTime.now()),
    );
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
          auth: widget.auth,
          directory: project.directory,
          title: project.name,
          onLoggedOut: widget.onLoggedOut,
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

  Future<void> _showProjectMenu(Project project) async {
    final l10n = AppLocalizations.of(context);
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(FLucideIcons.pencil),
              title: Text(l10n.rename),
              onTap: () {
                Navigator.pop(context);
                _renameProject(project);
              },
            ),
            ListTile(
              leading: const Icon(FLucideIcons.fileArchive),
              title: Text(l10n.exportZip),
              onTap: () {
                Navigator.pop(context);
                _exportProject(project);
              },
            ),
            ListTile(
              leading: const Icon(FLucideIcons.trash2),
              title: Text(l10n.remove),
              onTap: () {
                Navigator.pop(context);
                _removeProject(project);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _renameProject(Project project) async {
    final l10n = AppLocalizations.of(context);
    final nameController = TextEditingController(text: project.name);
    final name = await showFDialog<String>(
      context: context,
      builder: (context, style, animation) => FDialog(
        animation: animation,
        builder: (context, style) => Padding(
          padding: const EdgeInsets.all(DesignTokens.spaceXl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.rename, style: style.titleTextStyle),
              const SizedBox(height: DesignTokens.spaceMd),
              FTextField(
                control: FTextFieldControl.managed(controller: nameController),
                autofocus: true,
              ),
              const SizedBox(height: DesignTokens.spaceLg),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  FButton(
                    variant: .ghost,
                    mainAxisSize: .min,
                    onPress: () => Navigator.pop(context),
                    child: Text(l10n.cancel),
                  ),
                  const SizedBox(width: DesignTokens.spaceSm),
                  FButton(
                    variant: .primary,
                    mainAxisSize: .min,
                    onPress: () => Navigator.pop(context, nameController.text.trim()),
                    child: Text(l10n.confirm),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (name == null || name.isEmpty) return;
    final updated = _projects
        .map((p) => p.directory == project.directory
            ? Project(directory: p.directory, name: name, lastOpenedAt: p.lastOpenedAt)
            : p)
        .toList();
    setState(() => _projects = updated);
    await ProjectStore.save(updated);
  }

  Future<void> _removeProject(Project project) async {
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;
    final confirmed = await showFDialog<bool>(
      context: context,
      builder: (context, style, animation) => FDialog(
        animation: animation,
        builder: (context, style) => Padding(
          padding: const EdgeInsets.all(DesignTokens.spaceXl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.remove, style: style.titleTextStyle),
              const SizedBox(height: DesignTokens.spaceMd),
              Text(project.name, style: TextStyle(color: colors.mutedForeground)),
              const SizedBox(height: DesignTokens.spaceLg),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  FButton(
                    variant: .ghost,
                    mainAxisSize: .min,
                    onPress: () => Navigator.pop(context, false),
                    child: Text(l10n.cancel),
                  ),
                  const SizedBox(width: DesignTokens.spaceSm),
                  FButton(
                    variant: .destructive,
                    mainAxisSize: .min,
                    onPress: () => Navigator.pop(context, true),
                    child: Text(l10n.remove),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (confirmed != true) return;
    final updated = _projects.where((p) => p.directory != project.directory).toList();
    setState(() => _projects = updated);
    _covers.remove(project.directory);
    await ProjectStore.save(updated);
  }

  Future<void> _exportProject(Project project) async {
    final l10n = AppLocalizations.of(context);
    try {
      final bytes = await WorkspaceFiles(
        client: widget.client,
        directory: project.directory,
      ).exportZip();
      if (!mounted) return;
      await Share.shareXFiles(
        [XFile.fromData(bytes, mimeType: "application/zip")],
        fileNameOverrides: ["${project.name}.zip"],
      );
    } catch (_) {
      if (!mounted) return;
      showFToast(context: context, title: Text(l10n.loadFailed));
    }
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
    return FScaffold(
      childPad: false,
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final collapsed = width < 600;
            final sidebarWidth = collapsed ? 72.0 : 240.0;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: sidebarWidth,
                  child: _buildSidebar(context, l10n, collapsed),
                ),
                Expanded(
                  child: _buildContent(context, l10n, width - sidebarWidth),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildSidebar(BuildContext context, AppLocalizations l10n, bool collapsed) {
    final colors = context.theme.colors;
    return Container(
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: colors.border)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 20, 12, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sidebarBrand(context, l10n, collapsed),
          const SizedBox(height: 24),
          _sidebarItem(
            context,
            icon: FLucideIcons.home,
            label: l10n.home,
            collapsed: collapsed,
            active: true,
            onTap: _scrollToTop,
          ),
          _sidebarItem(
            context,
            icon: FLucideIcons.folder,
            label: l10n.projects,
            collapsed: collapsed,
            onTap: _scrollToProjects,
          ),
          const Divider(height: 24, color: Colors.transparent),
          _sidebarItem(
            context,
            icon: FLucideIcons.image,
            label: l10n.assetLibrary,
            collapsed: collapsed,
            onTap: _openAssetLibrary,
          ),
          const Spacer(),
          _sidebarItem(
            context,
            icon: FLucideIcons.monitor,
            label: l10n.deviceLink,
            collapsed: collapsed,
            onTap: () => _showDesktopOnly(l10n),
          ),
          _sidebarItem(
            context,
            icon: FLucideIcons.settings,
            label: l10n.settings,
            collapsed: collapsed,
            onTap: _openSettings,
          ),
          _sidebarItem(
            context,
            icon: FLucideIcons.user,
            label: _username ?? l10n.login,
            collapsed: collapsed,
            onTap: _logout,
          ),
        ],
      ),
    );
  }

  Widget _sidebarBrand(BuildContext context, AppLocalizations l10n, bool collapsed) {
    final colors = context.theme.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: colors.primary,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(FLucideIcons.clapperboard, size: 18, color: Colors.white),
          ),
          if (!collapsed) ...[
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                l10n.appName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.5,
                  color: colors.foreground,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _sidebarItem(
    BuildContext context, {
    required IconData icon,
    required String label,
    required bool collapsed,
    required VoidCallback onTap,
    bool active = false,
  }) {
    final colors = context.theme.colors;
    final foreground = active ? colors.foreground : colors.mutedForeground;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: active ? colors.primary.withValues(alpha: 0.1) : Colors.transparent,
        borderRadius: BorderRadius.circular(DesignTokens.radius),
        child: InkWell(
          borderRadius: BorderRadius.circular(DesignTokens.radius),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: collapsed
                ? Icon(icon, size: 18, color: foreground)
                : Row(
                    children: [
                      Icon(icon, size: 18, color: foreground),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            height: 1.5,
                            color: foreground,
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, AppLocalizations l10n, double contentWidth) {
    final columns = contentWidth < 560 ? 1 : (contentWidth / 220).floor().clamp(1, 6).toInt();
    final hPadding = contentWidth < 560 ? 16.0 : 24.0;
    final gridWidth = contentWidth - hPadding * 2;
    final cardWidth = (gridWidth - (columns - 1) * 20.0) / columns;
    return ListView(
      controller: _scrollController,
      padding: EdgeInsets.fromLTRB(hPadding, 24, hPadding, 40),
      children: [
        _buildCreationPanel(context, l10n),
        const SizedBox(height: 56),
        _buildProjectTabs(context, l10n),
        const SizedBox(height: 20),
        if (_projectTypeLocal)
          Wrap(
            key: _projectsKey,
            spacing: 20,
            runSpacing: 20,
            children: [
              SizedBox(width: cardWidth, height: 240, child: _buildLaunchCard(context)),
              for (final project in _projects)
                SizedBox(width: cardWidth, height: 240, child: _buildProjectCard(context, project)),
            ],
          )
        else
          const SizedBox(height: 240),
      ],
    );
  }

  Widget _buildProjectTabs(BuildContext context, AppLocalizations l10n) {
    return Row(
      children: [
        _projectTab(context, l10n.projects, _projectTypeLocal, () => setState(() => _projectTypeLocal = true)),
        const SizedBox(width: 28),
        _projectTab(context, l10n.teamProject, !_projectTypeLocal, () => setState(() => _projectTypeLocal = false)),
      ],
    );
  }

  Widget _projectTab(BuildContext context, String label, bool active, VoidCallback onTap) {
    final colors = context.theme.colors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(DesignTokens.radiusSmall),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w600,
            height: 1.5,
            color: active ? colors.foreground : colors.mutedForeground,
          ),
        ),
      ),
    );
  }

  void _scrollToTop() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _scrollToProjects() {
    final context = _projectsKey.currentContext;
    if (context != null) {
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _showDesktopOnly(AppLocalizations l10n) {
    showFToast(context: context, title: Text(l10n.desktopOnly));
  }

  Widget _moreButton(BuildContext context, Project project) {
    return Material(
      color: Colors.black26,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => _showProjectMenu(project),
        child: const Padding(
          padding: EdgeInsets.all(6),
          child: Icon(FLucideIcons.moreHorizontal, size: 18, color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildCreationPanel(BuildContext context, AppLocalizations l10n) {
    final colors = context.theme.colors;
    return Align(
      alignment: Alignment.topCenter,
      heightFactor: 1.0,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(FLucideIcons.sparkles, size: 32, color: colors.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    "今天要做点什么？",
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w500,
                      letterSpacing: -0.5,
                      height: 1.3,
                      color: colors.foreground,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),
            _buildPromptCard(context, l10n),
          ],
        ),
      ),
    );
  }

  Widget _buildPromptCard(BuildContext context, AppLocalizations l10n) {
    final colors = context.theme.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? DesignTokens.surfaceOverlayDark : DesignTokens.surfaceOverlayLight;
    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(DesignTokens.radiusCardLarge),
        border: Border.all(color: colors.border),
        boxShadow: const [
          BoxShadow(
            color: DesignTokens.shadowCard,
            offset: Offset(0, 12),
            blurRadius: 36,
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(22, 20, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            minLines: 3,
            maxLines: 8,
            style: TextStyle(fontSize: 15, height: 1.9, color: colors.foreground),
            decoration: InputDecoration(
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: EdgeInsets.zero,
              hintText: "描述你想创作的内容，让灵感从这里开始…",
              hintStyle: TextStyle(fontSize: 15, height: 1.9, color: colors.mutedForeground),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              FButton.icon(
                variant: .primary,
                onPress: _addProject,
                semanticsTooltip: l10n.addProject,
                child: const Icon(FLucideIcons.arrowUp),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLaunchCard(BuildContext context) {
    final colors = context.theme.colors;
    return _cardShell(
      context,
      onTap: _addProject,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(
              color: DesignTokens.primary,
              shape: BoxShape.circle,
            ),
            child: const Icon(FLucideIcons.plus, color: Colors.white),
          ),
          const SizedBox(height: 12),
          Text(
            "新建项目",
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, height: 1.8, color: colors.foreground),
          ),
          const SizedBox(height: 6),
          Text(
            "或打开已有项目",
            style: TextStyle(fontSize: 13, height: 1.6, color: colors.mutedForeground),
          ),
        ],
      ),
    );
  }

  Widget _buildProjectCard(BuildContext context, Project project) {
    final colors = context.theme.colors;
    final cover = _covers[project.directory];
    return _cardShell(
      context,
      onTap: () => _openProject(project),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (cover != null)
                  Image.memory(cover, fit: BoxFit.cover)
                else
                  Center(
                    child: Icon(FLucideIcons.folder, size: 40, color: colors.mutedForeground),
                  ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: _moreButton(context, project),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(DesignTokens.spaceLg),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: colors.border)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  project.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.5, color: colors.foreground),
                ),
                const SizedBox(height: 6),
                Text(
                  "最近打开 ${_formatLastOpened(project.lastOpenedAt)}",
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, height: 1.6, color: colors.mutedForeground),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _cardShell(BuildContext context, {required VoidCallback onTap, required Widget child}) {
    final colors = context.theme.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? DesignTokens.surfaceOverlayDark : DesignTokens.surfaceOverlayLight;
    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
        border: Border.all(color: colors.border),
        boxShadow: const [
          BoxShadow(color: DesignTokens.shadowLighter, offset: Offset(0, 1), blurRadius: 4),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: child,
        ),
      ),
    );
  }

  String _formatLastOpened(DateTime time) {
    String two(int value) => value.toString().padLeft(2, "0");
    return "${time.year}-${two(time.month)}-${two(time.day)} ${two(time.hour)}:${two(time.minute)}";
  }
}

/// 目录选择器：浏览服务端工作区目录与文件，支持新建/重命名/删除文件夹，选择后返回绝对路径。
class DirectoryPickerPage extends StatefulWidget {
  final ApiClient client;

  const DirectoryPickerPage({super.key, required this.client});

  @override
  State<DirectoryPickerPage> createState() => _DirectoryPickerPageState();
}

class _DirectoryPickerPageState extends State<DirectoryPickerPage> {
  String _path = "";
  String _absolutePath = "";
  String? _parent;
  List<Map<String, dynamic>> _entries = [];
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
      final info = await widget.client
          .getData("/api/workspaces/list", query: {"path": _path}) as Map<String, dynamic>;
      final absolutePath = info["absolutePath"] as String? ?? "";
      final parent = info["parent"] as String?;
      final listing = await WorkspaceFiles(client: widget.client, directory: absolutePath)
          .list("");
      final entries = (listing["entries"] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      entries.sort((a, b) {
        final at = a["type"] == "directory" ? 0 : 1;
        final bt = b["type"] == "directory" ? 0 : 1;
        if (at != bt) return at - bt;
        return (a["name"] as String? ?? "").compareTo(b["name"] as String? ?? "");
      });
      if (!mounted) return;
      setState(() {
        _absolutePath = absolutePath;
        _parent = parent;
        _entries = entries;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
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

  void _confirm() {
    Navigator.of(context).pop(_absolutePath);
  }

  bool _validName(String name) {
    if (name.isEmpty || name == "." || name == "..") return false;
    if (RegExp(r'[\\/:*?"<>|\u0000-\u001f]').hasMatch(name)) return false;
    return true;
  }

  Future<void> _manageEntry(String action, [Map<String, dynamic>? entry]) async {
    final l10n = AppLocalizations.of(context);
    final files = WorkspaceFiles(client: widget.client, directory: _absolutePath);

    if (action == "remove") {
      final isDir = entry?["type"] == "directory";
      final confirmed = await showFDialog<bool>(
        context: context,
        builder: (context, style, animation) => FDialog(
          animation: animation,
          builder: (context, style) => Padding(
            padding: const EdgeInsets.all(DesignTokens.spaceXl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l10n.remove, style: style.titleTextStyle),
                const SizedBox(height: DesignTokens.spaceMd),
                Text(entry?["name"] ?? ""),
                const SizedBox(height: DesignTokens.spaceLg),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    FButton(
                      variant: .ghost,
                      mainAxisSize: .min,
                      onPress: () => Navigator.pop(context, false),
                      child: Text(l10n.cancel),
                    ),
                    const SizedBox(width: DesignTokens.spaceSm),
                    FButton(
                      variant: .destructive,
                      mainAxisSize: .min,
                      onPress: () => Navigator.pop(context, true),
                      child: Text(l10n.remove),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
      if (confirmed != true) return;
      try {
        await files.remove(entry!["path"] as String, isDir);
        await _load();
      } catch (e) {
        if (!mounted) return;
        showFToast(context: context, variant: .destructive, title: Text(e.toString()));
      }
      return;
    }

    final initialName = action == "rename" ? (entry?["name"] as String?) ?? "" : "";
    final controller = TextEditingController(text: initialName);
    final name = await showFDialog<String>(
      context: context,
      builder: (context, style, animation) => FDialog(
        animation: animation,
        builder: (context, style) => Padding(
          padding: const EdgeInsets.all(DesignTokens.spaceXl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                action == "mkdir" ? l10n.newFolder : l10n.rename,
                style: style.titleTextStyle,
              ),
              const SizedBox(height: DesignTokens.spaceMd),
              FTextField(
                control: FTextFieldControl.managed(controller: controller),
                autofocus: true,
              ),
              const SizedBox(height: DesignTokens.spaceLg),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  FButton(
                    variant: .ghost,
                    mainAxisSize: .min,
                    onPress: () => Navigator.pop(context),
                    child: Text(l10n.cancel),
                  ),
                  const SizedBox(width: DesignTokens.spaceSm),
                  FButton(
                    variant: .primary,
                    mainAxisSize: .min,
                    onPress: () => Navigator.pop(context, controller.text.trim()),
                    child: Text(l10n.confirm),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (name == null) return;
    if (!mounted) return;
    if (!_validName(name)) {
      showFToast(context: context, variant: .destructive, title: Text(l10n.invalidName));
      return;
    }
    try {
      if (action == "mkdir") {
        await files.mkdir(name);
      } else {
        if (name == entry?["name"]) return;
        await files.rename(entry!["path"] as String, name);
      }
      await _load();
    } catch (e) {
      if (!mounted) return;
      showFToast(context: context, variant: .destructive, title: Text(e.toString()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            DesignTokens.spaceLg,
            DesignTokens.spaceLg,
            DesignTokens.spaceLg,
            DesignTokens.spaceSm,
          ),
          child: Row(
            children: [
              FButton.icon(
                variant: .ghost,
                semanticsTooltip: l10n.parentDirectory,
                onPress: _parent == null ? null : () => _enter(_parent!),
                child: const Icon(FLucideIcons.arrowLeft),
              ),
              const SizedBox(width: DesignTokens.spaceSm),
              Expanded(
                child: Text(
                  _absolutePath.isEmpty ? l10n.selectDirectory : _absolutePath,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.theme.typography.body.sm,
                ),
              ),
              FButton.icon(
                variant: .ghost,
                semanticsTooltip: l10n.newFolder,
                onPress: () => _manageEntry("mkdir"),
                child: const Icon(FLucideIcons.folderPlus),
              ),
            ],
          ),
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 320),
          child: _buildBody(l10n),
        ),
        Padding(
          padding: const EdgeInsets.all(DesignTokens.spaceLg),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              FButton(
                variant: .ghost,
                mainAxisSize: .min,
                onPress: () => Navigator.pop(context),
                child: Text(l10n.cancel),
              ),
              const SizedBox(width: DesignTokens.spaceSm),
              FButton(
                variant: .primary,
                mainAxisSize: .min,
                onPress: _absolutePath.isEmpty ? null : _confirm,
                child: Text(l10n.useThisDirectory),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBody(AppLocalizations l10n) {
    if (_loading) {
      return const SizedBox(
        height: 220,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return SizedBox(
        height: 220,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: DesignTokens.spaceSm),
              FButton(
                variant: .outline,
                mainAxisSize: .min,
                onPress: _load,
                child: Text(l10n.retry),
              ),
            ],
          ),
        ),
      );
    }
    if (_entries.isEmpty) {
      return SizedBox(
        height: 120,
        child: Center(child: Text(l10n.noFiles)),
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      itemCount: _entries.length,
      itemBuilder: (context, index) {
        final entry = _entries[index];
        final isDir = entry["type"] == "directory";
        final name = entry["name"] as String? ?? "";
        return FTile(
          title: Row(
            children: [
              Icon(isDir ? FLucideIcons.folder : FLucideIcons.file, size: 16),
              const SizedBox(width: DesignTokens.spaceSm),
              Expanded(
                child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          onPress: isDir ? () => _enter(entry["path"] as String) : null,
          suffix: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FButton.icon(
                variant: .ghost,
                semanticsTooltip: l10n.rename,
                onPress: () => _manageEntry("rename", entry),
                child: const Icon(FLucideIcons.pencil),
              ),
              FButton.icon(
                variant: .destructive,
                semanticsTooltip: l10n.remove,
                onPress: () => _manageEntry("remove", entry),
                child: const Icon(FLucideIcons.trash2),
              ),
            ],
          ),
        );
      },
    );
  }
}
