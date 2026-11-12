import "apiClient.dart";

/// 登录会话信息（对应服务端 `/api/auth/session` 返回）。
class AuthSession {
  final bool authenticated;
  final String? sub;
  final String? username;
  final String? email;

  const AuthSession({required this.authenticated, this.sub, this.username, this.email});
}

/// 鉴权服务：校验会话、登出。
class AuthService {
  final ApiClient client;

  AuthService(this.client);

  Future<AuthSession> session() async {
    final data = await client.getData("/api/auth/session") as Map<String, dynamic>;
    return AuthSession(
      authenticated: data["authenticated"] == true,
      sub: data["sub"] as String?,
      username: data["username"] as String?,
      email: data["email"] as String?,
    );
  }

  Future<void> logout() async {
    await client.postData("/api/auth/logout");
  }
}
