import "package:flutter/material.dart";
import "package:forui/forui.dart";

import "../../core/apiClient.dart";
import "../../core/sessionStore.dart";
import "../../shared/appLocalizations.dart";
import "../../shared/designTokens.dart";
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
    final selected = await showFDialog<String>(
      context: context,
      builder: (context, style, animation) => FDialog(
        animation: animation,
        builder: (context, style) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.language, style: style.titleTextStyle),
              const SizedBox(height: 8),
              for (final option in options)
                FButton(
                  variant: FButtonVariant.ghost,
                  onPress: () => Navigator.pop(context, option.key),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(option.value),
                  ),
                ),
            ],
          ),
        ),
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
    final selected = await showFDialog<String>(
      context: context,
      builder: (context, style, animation) => FDialog(
        animation: animation,
        builder: (context, style) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.theme, style: style.titleTextStyle),
              const SizedBox(height: 8),
              for (final option in options)
                FButton(
                  variant: FButtonVariant.ghost,
                  onPress: () => Navigator.pop(context, option.key),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(option.value),
                  ),
                ),
            ],
          ),
        ),
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
    final value = await showFDialog<String>(
      context: context,
      builder: (context, style, animation) => FDialog(
        animation: animation,
        builder: (context, style) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.serverAddress, style: style.titleTextStyle),
              const SizedBox(height: 12),
              FTextField(
                control: FTextFieldControl.managed(controller: controller),
                keyboardType: TextInputType.url,
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  FButton(
                    variant: FButtonVariant.ghost,
                    mainAxisSize: MainAxisSize.min,
                    onPress: () => Navigator.pop(context),
                    child: Text(l10n.cancel),
                  ),
                  const SizedBox(width: 8),
                  FButton(
                    variant: FButtonVariant.primary,
                    mainAxisSize: MainAxisSize.min,
                    onPress: () => Navigator.pop(context, controller.text.trim()),
                    child: Text(l10n.save),
                  ),
                ],
              ),
            ],
          ),
        ),
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
    return FScaffold(
      header: FHeader(title: Text(l10n.settings)),
      childPad: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: FCard(
          clipBehavior: Clip.antiAlias,
          child: ListView(
            children: [
              _sectionHeader(l10n.general),
              FTile(
                prefix: Icon(FLucideIcons.languages),
                title: Text(l10n.language),
                subtitle: Text(_languageLabel(l10n)),
                onPress: _selectLanguage,
              ),
              FTile(
                prefix: Icon(FLucideIcons.sunMoon),
                title: Text(l10n.theme),
                subtitle: Text(_themeLabel(l10n)),
                onPress: _selectTheme,
              ),
              FTile(
                prefix: Icon(FLucideIcons.server),
                title: Text(l10n.serverAddress),
                subtitle: Text(_baseUrl),
                onPress: _editServerAddress,
              ),
              const FDivider(),
              _sectionHeader(l10n.deviceLink),
              _buildDeviceLink(l10n),
              const FDivider(),
              _sectionHeader(l10n.pluginAndMcp),
              _buildMcp(l10n),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: context.theme.typography.body.sm.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildDeviceLink(AppLocalizations l10n) {
    if (_deviceToken != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FTile(
            prefix: Icon(FLucideIcons.monitorSmartphone),
            title: Text(l10n.paired),
            subtitle: Text(_deviceName ?? ""),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: FButton(
              variant: FButtonVariant.outline,
              onPress: _unpair,
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
          Text(
            l10n.notPaired,
            style: context.theme.typography.body.xs.copyWith(
              color: context.theme.colors.mutedForeground,
            ),
          ),
          const SizedBox(height: 12),
          FTextField(
            control: FTextFieldControl.managed(controller: _pairCodeController),
            label: Text(l10n.pairCode),
          ),
          const SizedBox(height: 12),
          FTextField(
            control: FTextFieldControl.managed(controller: _deviceNameController),
            label: Text(l10n.deviceName),
          ),
          if (_pairError != null) ...[
            const SizedBox(height: 8),
            Text(
              _pairError!,
              style: const TextStyle(color: DesignTokens.danger),
            ),
          ],
          const SizedBox(height: 12),
          FButton(
            onPress: _pairing ? null : _pair,
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
            style: context.theme.typography.body.xs.copyWith(
              color: context.theme.colors.mutedForeground,
            ),
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
            (server) => FTile(
              prefix: Icon(
                server.enabled ? FLucideIcons.circleCheck : FLucideIcons.circleX,
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
