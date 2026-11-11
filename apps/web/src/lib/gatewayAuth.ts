// ACT: BFF 模式 — 前端不接触任何 OAuth token，只通过 HttpOnly cookie 与 server 端 session 交互。

export interface AuthUser {
  sub: string;
  username?: string;
  email?: string;
}

export interface AuthSession {
  authenticated: boolean;
  sub?: string;
  username?: string;
  email?: string;
}

/** 从 server 获取当前 session 状态。任何错误都视为未登录。 */
export async function fetchAuthSession(): Promise<AuthSession> {
  try {
    const res = await fetch("/api/auth/session", { credentials: "include" });
    if (!res.ok) return { authenticated: false };
    const json = await res.json() as { code: number; data: AuthSession };
    if (json.code !== 200 || !json.data) return { authenticated: false };
    return json.data;
  } catch {
    return { authenticated: false };
  }
}

/** 浏览器级跳转到 /api/auth/start，由 server 处理 PKCE 并 302 到 new-api。 */
export function redirectToLogin(): never {
  window.location.href = "/api/auth/start";
  // redirectToLogin 永远不会返回；此处仅用于满足 TypeScript 返回类型。
  throw new Error("redirectToLogin 触发了浏览器跳转，不应继续执行。");
}

/** 通知 server 注销，然后整页刷新清掉前端残留状态。 */
export async function logout(): Promise<void> {
  try {
    await fetch("/api/auth/logout", { method: "POST", credentials: "include" });
  } finally {
    window.location.reload();
  }
}
