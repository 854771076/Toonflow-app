import "package:flutter/material.dart";
import "package:webview_flutter/webview_flutter.dart";

import "../../core/apiClient.dart";
import "../../core/sessionStore.dart";
import "../../shared/appLocalizations.dart";
import "../settings/settingsPage.dart";

/// 登录页：输入服务端地址，通过 WebView 走服务端 OAuth2 授权。
class LoginPage extends StatefulWidget {
  final ApiClient client;
  final Future<void> Function() onLoggedIn;
  final VoidCallback onToggleLanguage;
  final void Function(String code)? onLocaleChanged;
  final void Function(String mode)? onThemeModeChanged;

  const LoginPage({
    super.key,
    required this.client,
    required this.onLoggedIn,
    required this.onToggleLanguage,
    this.onLocaleChanged,
    this.onThemeModeChanged,
  });

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _baseUrlController = TextEditingController();
  bool _webViewMode = false;
  bool _connecting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    SessionStore.getBaseUrl().then((url) {
      if (mounted) _baseUrlController.text = url;
    });
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    super.dispose();
  }

  Future<void> _openLogin() async {
    final baseUrl = _baseUrlController.text.trim();
    if (baseUrl.isEmpty) return;
    setState(() {
      _connecting = true;
      _error = null;
    });
    await SessionStore.saveBaseUrl(baseUrl);
    if (!mounted) return;
    setState(() {
      _connecting = false;
      _webViewMode = true;
    });
  }

  Future<void> _onSession(String cookie) async {
    widget.client.setSession(cookie);
    await SessionStore.saveSession(cookie);
    await widget.onLoggedIn();
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
    if (_webViewMode) {
      return _buildWebView(context);
    }
    return _buildForm(context);
  }

  Widget _buildForm(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.login),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: _openSettings,
            tooltip: l10n.settings,
          ),
          IconButton(
            icon: const Icon(Icons.translate),
            onPressed: widget.onToggleLanguage,
            tooltip: l10n.switchLanguage,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.serverAddress,
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _baseUrlController,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                hintText: "http://127.0.0.1:3100",
                border: const OutlineInputBorder(),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _connecting ? null : _openLogin,
              child: _connecting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(l10n.connect),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWebView(BuildContext context) {
    final baseUrl = _baseUrlController.text.trim();
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).login),
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => setState(() => _webViewMode = false),
          ),
        ],
      ),
      body: _LoginWebView(baseUrl: baseUrl, onSession: _onSession),
    );
  }
}

/// 承载 OAuth2 授权流程的 WebView，完成后提取 `gateway_session` cookie。
class _LoginWebView extends StatefulWidget {
  final String baseUrl;
  final Future<void> Function(String cookie) onSession;

  const _LoginWebView({required this.baseUrl, required this.onSession});

  @override
  State<_LoginWebView> createState() => _LoginWebViewState();
}

class _LoginWebViewState extends State<_LoginWebView> {
  late final WebViewController _controller;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (url) => _onPageFinished(url),
        ),
      )
      ..loadRequest(Uri.parse("${widget.baseUrl}/api/auth/start"));
  }

  Future<void> _onPageFinished(String url) async {
    if (_done) return;
    if (!url.startsWith(widget.baseUrl)) return;
    if (url.contains("/api/auth")) return;
    try {
      final cookies =
          await WebViewCookieManager().getCookies(domain: Uri.parse(widget.baseUrl));
      for (final cookie in cookies) {
        if (cookie.name == "gateway_session" && cookie.value.isNotEmpty) {
          _done = true;
          await widget.onSession(cookie.value);
          return;
        }
      }
    } catch (_) {
      // 提取失败则等待下一次导航完成。
    }
  }

  @override
  Widget build(BuildContext context) {
    return WebViewWidget(controller: _controller);
  }
}
