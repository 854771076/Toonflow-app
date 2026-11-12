import "package:flutter/material.dart";

import "../../core/apiClient.dart";
import "../../core/sessionStore.dart";
import "../../shared/appLocalizations.dart";
import "settingsApi.dart";

/// 设置页：集中通用设置、设备互联与插件/MCP 只读浏览。
///
/// 语言与主题切换通过回调通知应用根组件刷新全局 locale/themeMode；
/// 未传入回调时仅持久化，下次启动生效。
class SettingsPage extends StatefulWidget {
  final ApiClient client;
  final void Function(String code)? onLocaleChanged;
  final void Function(String mode)? onThemeModeChanged;

  const SettingsPage({
    super.key,
    required this.client,
    this.onLocaleChanged,
    this.onThemeModeChanged,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final SettingsApi _settingsApi;

  String _language = "system";
  String _themeMode = "dark";
  String _baseUrl = "";

  String? _deviceToken;
  String? _deviceName;

  final TextEditingController _pairCodeController = TextEditingController();
  final TextEditingController _deviceNameController = TextEditingController();
  bool _pairing = false;
  String? _pairError;

  List<McpServer> _mcpServers = [];
  bool _mcpLoading = true;
  String? _mcpError;

  @override
  void initState() {
    super.initState();
    _settingsApi = SettingsApi(widget.client);
    _restore();
    _loadMcpServers();
  }

  @override
  void dispose() {
    _pairCodeController.dispose();
    _deviceNameController.dispose();
    super.dispose();
  }

  Future<void> _restore() async {
    final language = await SessionStore.getLanguage();
    final themeMode = await SessionStore.getThemeMode();
    final baseUrl = await SessionStore.getBaseUrl();
    final deviceToken = await SessionStore.getDeviceToken();
    final deviceName = await SessionStore.getDeviceName();
    if (!mounted) return;
    setState(() {
      _language = language;
      _themeMode = themeMode;
      _baseUrl = baseUrl;
      _deviceToken =
          (deviceToken == null || deviceToken.isEmpty) ? null : deviceToken;
      _deviceName = deviceName;
    });
  }

  Future<void> _loadMcpServers() async {
    setState(() {
      _mcpLoading = true;
      _mcpError = null;
    });
    try {
      final servers = await _settingsApi.listMcpServers();
      if (!mounted) return;
      setState(() {
        _mcpServers = servers;
        _mcpLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _mcpError = e.toString();
        _mcpLoading = false;
      });
    }
  }

  Future<void> _selectLanguage() async {
    final l10n = AppLocalizations.of(context);
    final options = <MapEntry<String, String>>[
      MapEntry("system", l10n.followSystem),
      const MapEntry("zh_CN", "简体中文"),
      const MapEntry("zh_TW", "繁體中文"),
      const MapEntry("en", "English"),
    ];
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(l10n.language),
        children: [
          for (final option in options)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, option.key),
              child: Text(option.value),
            ),
        ],
      ),
    );
    if (selected == null || selected == _language) return;
    await SessionStore.saveLanguage(selected);
    widget.onLocaleChanged?.call(selected);
    if (mounted) setState(() => _language = selected);
  }

  Future<void> _selectTheme() async {
    final l10n = AppLocalizations.of(context);
    final options = <MapEntry<String, String>>[
      MapEntry("system", l10n.followSystem),
      MapEntry("light", l10n.light),
      MapEntry("dark", l10n.dark),
    ];
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(l10n.theme),
        children: [
          for (final option in options)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, option.key),
              child: Text(option.value),
            ),
        ],
      ),
    );
    if (selected == null || selected == _themeMode) return;
    await SessionStore.saveThemeMode(selected);
    widget.onThemeModeChanged?.call(selected);
    if (mounted) setState(() => _themeMode = selected);
  }

  Future<void> _editServerAddress() async {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController(text: _baseUrl);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.serverAddress),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.url,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(l10n.save),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || value.isEmpty) return;
    await SessionStore.saveBaseUrl(value);
    if (mounted) setState(() => _baseUrl = value);
  }

  Future<void> _pair() async {
    final code = _pairCodeController.text.trim();
    final name = _deviceNameController.text.trim();
    if (code.isEmpty || name.isEmpty) return;
    setState(() {
      _pairing = true;
      _pairError = null;
    });
    try {
      final result = await _settingsApi.pair(code, name);
      widget.client.setDeviceToken(result.deviceToken);
      await SessionStore.saveDeviceToken(result.deviceToken);
      await SessionStore.saveDeviceName(name);
      if (!mounted) return;
      setState(() {
        _deviceToken = result.deviceToken;
        _deviceName = name;
        _pairing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _pairing = false;
        _pairError = e.toString();
      });
    }
  }

  Future<void> _unpair() async {
    // ACT: 仅清除本地 token，不调用服务端 revoke（revoke 是桌面端本机操作）。
    widget.client.setDeviceToken(null);
    await SessionStore.saveDeviceToken(null);
    await SessionStore.saveDeviceName(null);
    if (!mounted) return;
    setState(() {
      _deviceToken = null;
      _deviceName = null;
    });
  }

  String _languageLabel(AppLocalizations l10n) {
    switch (_language) {
      case "zh_CN":
        return "简体中文";
      case "zh_TW":
        return "繁體中文";
      case "en":
        return "English";
      default:
        return l10n.followSystem;
    }
  }

  String _themeLabel(AppLocalizations l10n) {
    switch (_themeMode) {
      case "light":
        return l10n.light;
      case "dark":
        return l10n.dark;
      default:
        return l10n.followSystem;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settings)),
      body: ListView(
        children: [
          _sectionHeader(l10n.general),
          ListTile(
            leading: const Icon(Icons.translate),
            title: Text(l10n.language),
            subtitle: Text(_languageLabel(l10n)),
            onTap: _selectLanguage,
          ),
          ListTile(
            leading: const Icon(Icons.brightness_6_outlined),
            title: Text(l10n.theme),
            subtitle: Text(_themeLabel(l10n)),
            onTap: _selectTheme,
          ),
          ListTile(
            leading: const Icon(Icons.dns_outlined),
            title: Text(l10n.serverAddress),
            subtitle: Text(_baseUrl),
            onTap: _editServerAddress,
          ),
          const Divider(),
          _sectionHeader(l10n.deviceLink),
          _buildDeviceLink(l10n),
          const Divider(),
          _sectionHeader(l10n.pluginAndMcp),
          _buildMcp(l10n),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(title, style: Theme.of(context).textTheme.titleSmall),
    );
  }

  Widget _buildDeviceLink(AppLocalizations l10n) {
    if (_deviceToken != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            leading: const Icon(Icons.phonelink_ring),
            title: Text(l10n.paired),
            subtitle: Text(_deviceName ?? ""),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: OutlinedButton(
              onPressed: _unpair,
              child: Text(l10n.unpair),
            ),
          ),
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.notPaired, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          TextField(
            controller: _pairCodeController,
            decoration: InputDecoration(
              labelText: l10n.pairCode,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _deviceNameController,
            decoration: InputDecoration(
              labelText: l10n.deviceName,
              border: const OutlineInputBorder(),
            ),
          ),
          if (_pairError != null) ...[
            const SizedBox(height: 8),
            Text(_pairError!, style: const TextStyle(color: Colors.red)),
          ],
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _pairing ? null : _pair,
            child: _pairing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(l10n.pair),
          ),
        ],
      ),
    );
  }

  Widget _buildMcp(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            l10n.desktopOnly,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        const SizedBox(height: 8),
        if (_mcpLoading)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_mcpError != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(_mcpError!),
          )
        else
          ..._mcpServers.map(
            (server) => ListTile(
              leading: Icon(
                server.enabled ? Icons.check_circle : Icons.cancel_outlined,
              ),
              title: Text(server.name),
              subtitle: Text(
                "${l10n.transport}: ${server.transport} · "
                "${l10n.status}: ${server.status} · "
                "${server.enabled ? l10n.enabled : l10n.disabled} · "
                "${server.toolCount}",
              ),
            ),
          ),
      ],
    );
  }
}
