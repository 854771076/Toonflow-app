// 前端用 Supabase signInWithOAuth 登录，拿到 provider_token 后交给后端 /api/auth/exchange 建立后端 session。
// 后端 session 仍是唯一登录态来源（HttpOnly cookie）；provider_token 仅用于首次建立，后续刷新由后端完成。

import { supabase } from "@/lib/supabase";

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

/** 用 Supabase session 里的 provider_token 与后端交换 gateway_session cookie。 */
async function exchangeProviderToken(): Promise<boolean> {
  const { data } = await supabase.auth.getSession();
  const token = data.session?.provider_token;
  if (!token) return false;
  const res = await fetch("/api/auth/exchange", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    credentials: "include",
    body: JSON.stringify({
      accessToken: token,
      refreshToken: data.session?.provider_refresh_token,
    }),
  });
  return res.ok;
}

/** 从 server 获取当前 session 状态。任何错误都视为未登录。 */
export async function fetchAuthSession(): Promise<AuthSession> {
  try {
    const res = await fetch("/api/auth/session", { credentials: "include" });
    if (res.ok) {
      const json = await res.json() as { code: number; data: AuthSession };
      if (json.code === 200 && json.data?.authenticated) return json.data;
    }
  } catch {
    // 继续尝试用 provider_token 重建后端 session。
  }

  if (await exchangeProviderToken()) {
    const res = await fetch("/api/auth/session", { credentials: "include" });
    if (res.ok) {
      const json = await res.json() as { code: number; data: AuthSession };
      if (json.code === 200 && json.data) return json.data;
    }
  }
  return { authenticated: false };
}

/** 触发 Supabase signInWithOAuth 跳转，登录后由 fetchAuthSession 完成 exchange。 */
export function redirectToLogin(): void {
  void supabase.auth.signInWithOAuth({ provider: "custom:newapi" });
}

/** 注销 Supabase 与后端 session，然后整页刷新清掉前端残留状态。 */
export async function logout(): Promise<void> {
  try {
    await supabase.auth.signOut();
  } finally {
    try {
      await fetch("/api/auth/logout", { method: "POST", credentials: "include" });
    } finally {
      window.location.reload();
    }
  }
}
