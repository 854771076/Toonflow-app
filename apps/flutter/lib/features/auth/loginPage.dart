import "dart:async";

import "package:flutter/material.dart";
import "package:forui/forui.dart";
import "package:supabase_flutter/supabase_flutter.dart";

import "../../core/apiClient.dart";
import "../../core/config.dart";
import "../../core/sessionStore.dart";
import "../../shared/appLocalizations.dart";
import "../../shared/designTokens.dart";

const String _loginTitle = "欢迎使用 YuYuer Drama";
const String _loginSubtitle = "使用 new-api 账号登录开始创作";
const String _loginButtonText = "使用 new-api 账号登录";

/// 登录页：通过 Supabase signInWithOAuth 拉起 new-api 授权登录。
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
  StreamSubscription<AuthState>? _authSub;
  bool _connecting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Supabase 完成 OAuth 回跳后触发 signedIn，携带 provider_token（new-api access token）。
    if (AppConfig.supabaseUrl.isNotEmpty) {
      _authSub = Supabase.instance.client.auth.onAuthStateChange.listen(_onAuthState);
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  void _onAuthState(AuthState state) {
    if (state.event != AuthChangeEvent.signedIn) return;
    final token = state.session?.providerToken;
    if (token == null || token.isEmpty) return;
    _exchange(token, state.session?.providerRefreshToken);
  }

  Future<void> _openLogin() async {
    if (AppConfig.supabaseUrl.isEmpty) {
      setState(() => _error = "未配置 Supabase 登录");
      return;
    }
    setState(() => _error = null);
    try {
      await Supabase.instance.client.auth.signInWithOAuth(
        OAuthProvider("custom:newapi"),
        redirectTo: "${AppConfig.authScheme}://auth/callback",
      );
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  /// 用 provider_token 与后端交换 gateway_session，成功后切到主界面。
  Future<void> _exchange(String accessToken, String? refreshToken) async {
    if (_connecting) return;
    setState(() {
      _connecting = true;
      _error = null;
    });
    try {
      final data = await widget.client.postData("/api/auth/exchange", body: {
        "accessToken": accessToken,
        if (refreshToken != null && refreshToken.isNotEmpty) "refreshToken": refreshToken,
      }) as Map<String, dynamic>;
      final sessionId = data["sessionId"] as String?;
      if (sessionId == null || sessionId.isEmpty) {
        throw const ApiException(-1, "登录失败");
      }
      await _onSession(sessionId);
    } catch (e) {
      if (mounted) {
        setState(() {
          _connecting = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _onSession(String cookie) async {
    widget.client.setSession(cookie);
    await SessionStore.saveSession(cookie);
    await widget.onLoggedIn();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return FScaffold(
      childPad: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: FCard(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _loginTitle,
                      textAlign: TextAlign.center,
                      style: context.theme.typography.display.xl.copyWith(
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                        color: context.theme.colors.foreground,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _loginSubtitle,
                      textAlign: TextAlign.center,
                      style: context.theme.typography.body.xs.copyWith(
                        color: context.theme.colors.mutedForeground,
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: DesignTokens.danger),
                      ),
                    ],
                    const SizedBox(height: 32),
                    FButton(
                      onPress: _connecting ? null : _openLogin,
                      size: .lg,
                      child: _connecting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text(_loginButtonText),
                    ),
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.center,
                      child: FButton.icon(
                        onPress: widget.onToggleLanguage,
                        variant: .ghost,
                        semanticsTooltip: l10n.switchLanguage,
                        child: const Icon(FLucideIcons.languages),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
