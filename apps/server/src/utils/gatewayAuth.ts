import { AsyncLocalStorage } from "node:async_hooks";
import { createHash, randomBytes, randomUUID } from "node:crypto";

export interface GatewaySession {
  sessionId: string;
  sub: string;
  username?: string;
  email?: string;
  accessToken: string;
  refreshToken?: string;
  tokenType: string;
  expiresAt: number;
  createdAt: number;
  refreshing?: boolean;
  invalidGrant?: boolean;
}

export interface GatewayConfig {
  baseUrl: string;
  publicUrl: string;
  clientId: string;
  scopes: string;
  appPublicUrl: string;
}

interface TokenResponse {
  access_token: string;
  token_type: string;
  expires_in?: number;
  refresh_token?: string;
  scope?: string;
}

interface UserinfoResponse {
  sub: string;
  username?: string;
  email?: string;
  [key: string]: unknown;
}

const sessionStore = new Map<string, GatewaySession>();
const sessionMaxAge = 7 * 24 * 60 * 60 * 1000; // 7 天
const refreshThreshold = 60 * 1000; // access token 过期前 60s 触发刷新
const refreshFailureRetryAfter = 5 * 60 * 1000; // refresh 失败后 5 分钟内不再重试

// 定时清理过期 session，避免内存泄漏
setInterval(() => {
  const now = Date.now();
  for (const [id, session] of sessionStore) {
    if (now - session.createdAt > sessionMaxAge) {
      sessionStore.delete(id);
    }
  }
}, 5 * 60 * 1000).unref?.();

export function getConfig(): GatewayConfig {
  const baseUrl = process.env.GATEWAY_BASE_URL?.trim();
  const clientId = process.env.GATEWAY_CLIENT_ID?.trim();
  const appPublicUrl = process.env.APP_PUBLIC_URL?.trim();

  if (!baseUrl || !clientId) {
    throw new Error("gateway 未配置：GATEWAY_BASE_URL 和 GATEWAY_CLIENT_ID 为必填");
  }
  if (!appPublicUrl) {
    throw new Error("gateway 未配置：APP_PUBLIC_URL 为必填");
  }

  const publicUrl = process.env.GATEWAY_PUBLIC_URL?.trim() || baseUrl;
  const scopes = process.env.GATEWAY_CLIENT_SCOPES?.trim() || "openid profile email api:read api:write";

  return {
    baseUrl,
    publicUrl,
    clientId,
    scopes,
    appPublicUrl,
  };
}

export function generateCodeVerifier(): string {
  const base = randomUUID() + randomUUID();
  return base.slice(0, 128);
}

export function computeCodeChallenge(verifier: string): string {
  return createHash("sha256").update(verifier).digest("base64url");
}

export function generateState(): string {
  return randomBytes(32).toString("hex");
}

export function buildAuthorizeUrl(params: {
  clientId: string;
  redirectUri: string;
  state: string;
  codeChallenge: string;
  scopes: string;
}): string {
  const url = new URL("/oauth/authorize", params.redirectUri.startsWith("http")
    ? (getConfig().publicUrl.startsWith("http") ? getConfig().publicUrl : getConfig().baseUrl)
    : getConfig().baseUrl);
  url.searchParams.set("response_type", "code");
  url.searchParams.set("client_id", params.clientId);
  url.searchParams.set("redirect_uri", params.redirectUri);
  url.searchParams.set("scope", params.scopes);
  url.searchParams.set("state", params.state);
  url.searchParams.set("code_challenge", params.codeChallenge);
  url.searchParams.set("code_challenge_method", "S256");
  return url.toString();
}

async function gatewayFetch(path: string, init: RequestInit): Promise<Response> {
  const cfg = getConfig();
  const url = new URL(path, cfg.baseUrl);
  const headers = new Headers(init.headers);
  if (!headers.has("Content-Type") && init.body) {
    headers.set("Content-Type", "application/x-www-form-urlencoded");
  }
  return fetch(url.toString(), { ...init, headers });
}

export async function exchangeCode(params: {
  code: string;
  redirectUri: string;
  clientId: string;
  codeVerifier: string;
}): Promise<TokenResponse> {
  const body = new URLSearchParams({
    grant_type: "authorization_code",
    code: params.code,
    redirect_uri: params.redirectUri,
    client_id: params.clientId,
    code_verifier: params.codeVerifier,
  });
  const res = await gatewayFetch("/oauth/token", {
    method: "POST",
    body,
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`exchangeCode failed ${res.status}: ${text}`);
  }
  return (await res.json()) as TokenResponse;
}

export async function refreshAccessToken(refreshToken: string): Promise<TokenResponse> {
  const cfg = getConfig();
  const body = new URLSearchParams({
    grant_type: "refresh_token",
    refresh_token: refreshToken,
    client_id: cfg.clientId,
  });
  const res = await gatewayFetch("/oauth/token", {
    method: "POST",
    body,
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`refreshAccessToken failed ${res.status}: ${text}`);
  }
  return (await res.json()) as TokenResponse;
}

export async function revokeToken(token: string): Promise<void> {
  const cfg = getConfig();
  const body = new URLSearchParams({
    token,
    client_id: cfg.clientId,
  });
  try {
    const res = await gatewayFetch("/oauth/revoke", {
      method: "POST",
      body,
    });
    // best effort，不关心结果
    void res;
  } catch {
    // 忽略网络错误
  }
}

export async function fetchUserinfo(accessToken: string): Promise<UserinfoResponse> {
  const res = await gatewayFetch("/oauth/userinfo", {
    method: "GET",
    headers: { Authorization: `Bearer ${accessToken}` },
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`fetchUserinfo failed ${res.status}: ${text}`);
  }
  return (await res.json()) as UserinfoResponse;
}

export function createSession(sessionId: string, tokens: TokenResponse, userinfo: UserinfoResponse): GatewaySession {
  const cfg = getConfig();
  const expiresInMs = (tokens.expires_in ?? 3600) * 1000;
  const session: GatewaySession = {
    sessionId,
    sub: userinfo.sub,
    username: userinfo.username,
    email: userinfo.email,
    accessToken: tokens.access_token,
    refreshToken: tokens.refresh_token,
    tokenType: tokens.token_type || "Bearer",
    expiresAt: Date.now() + expiresInMs,
    createdAt: Date.now(),
  };
  sessionStore.set(sessionId, session);
  return session;
}

export function getSession(sessionId: string): GatewaySession | undefined {
  return sessionStore.get(sessionId);
}

// 请求级会话上下文：AI 模型解析等深层调用无需逐层传递 sessionId。
const requestGatewaySession = new AsyncLocalStorage<string>();

export function runWithGatewaySession<T>(sessionId: string | undefined, run: () => T): T {
  return sessionId ? requestGatewaySession.run(sessionId, run) : run();
}

export function currentGatewaySessionId(): string | undefined {
  return requestGatewaySession.getStore();
}

export async function getAccessToken(sessionId?: string): Promise<string> {
  const id = sessionId ?? currentGatewaySessionId();
  const session = id ? sessionStore.get(id) : undefined;
  if (!id || !session) throw Object.assign(new Error("登录已失效，请重新登录"), { status: 401 });
  const result = await getOrRefreshAccessToken(id);
  if (!result.accessToken || result.invalidGrant) throw Object.assign(new Error("登录已失效，请重新登录"), { status: 401 });
  return result.accessToken;
}

export async function gatewayApiFetch(path: string, init: RequestInit = {}, sessionId?: string): Promise<Response> {
  const accessToken = await getAccessToken(sessionId);
  const headers = new Headers(init.headers);
  headers.set("Authorization", `Bearer ${accessToken}`);
  return fetch(new URL(path, getConfig().baseUrl).toString(), { ...init, headers });
}

let statusCache: { expiresAt: number; value: GatewayStatus } | undefined;

export interface GatewayStatus {
  quotaPerUnit: number;
  displayType: string;
  usdExchangeRate: number;
}

export async function getGatewayStatus(): Promise<GatewayStatus> {
  if (statusCache && statusCache.expiresAt > Date.now()) return statusCache.value;
  const res = await fetch(new URL("/api/status", getConfig().baseUrl).toString());
  if (!res.ok) throw Object.assign(new Error("获取网关状态失败"), { status: 502 });
  const body = (await res.json()) as Record<string, unknown>;
  const data = (body.data ?? body) as Record<string, unknown>;
  const value: GatewayStatus = {
    quotaPerUnit: typeof data.quota_per_unit === "number" ? data.quota_per_unit : 500000,
    displayType: typeof data.quota_display_type === "string" ? data.quota_display_type : "USD",
    usdExchangeRate: typeof data.usd_exchange_rate === "number" ? data.usd_exchange_rate : 1,
  };
  statusCache = { expiresAt: Date.now() + 10 * 60 * 1000, value };
  return value;
}

export function deleteSession(sessionId: string): void {
  sessionStore.delete(sessionId);
}

interface GetOrRefreshResult {
  accessToken: string | null;
  needsRefresh: boolean;
  invalidGrant?: boolean;
}

// 记录每个 session 的 refresh 失败时间，短时间内不重复刷新
const refreshFailureAt = new Map<string, number>();

export async function getOrRefreshAccessToken(sessionId: string): Promise<GetOrRefreshResult> {
  const session = sessionStore.get(sessionId);
  if (!session) return { accessToken: null, needsRefresh: false };

  // 已确认 refresh token 永久失效，不再尝试
  if (session.invalidGrant) {
    return { accessToken: null, needsRefresh: true, invalidGrant: true };
  }

  const now = Date.now();
  const timeUntilExpiry = session.expiresAt - now;

  // 还没到刷新窗口，直接返回
  if (timeUntilExpiry > refreshThreshold) {
    return { accessToken: session.accessToken, needsRefresh: false };
  }

  // 没 refresh_token，只能用现有 accessToken（可能已经快过期）
  if (!session.refreshToken) {
    return { accessToken: session.accessToken, needsRefresh: true };
  }

  // 已有并发请求在刷新，直接返回旧 token 让它完成
  if (session.refreshing) {
    return { accessToken: session.accessToken, needsRefresh: true };
  }

  // 最近刚刷新失败过（网络错误），短时间内不再试
  const lastFailure = refreshFailureAt.get(sessionId);
  if (lastFailure && now - lastFailure < refreshFailureRetryAfter) {
    return { accessToken: session.accessToken, needsRefresh: true };
  }

  session.refreshing = true;
  try {
    const tokens = await refreshAccessToken(session.refreshToken);
    const expiresInMs = (tokens.expires_in ?? 3600) * 1000;
    session.accessToken = tokens.access_token;
    // new-api 轮换 refresh token
    if (tokens.refresh_token) session.refreshToken = tokens.refresh_token;
    session.expiresAt = Date.now() + expiresInMs;
    refreshFailureAt.delete(sessionId);
    return { accessToken: session.accessToken, needsRefresh: false };
  } catch (error) {
    const msg = error instanceof Error ? error.message : String(error);
    if (msg.includes("invalid_grant") || msg.includes("401") || msg.includes("400")) {
      session.invalidGrant = true;
      refreshFailureAt.set(sessionId, now);
      return { accessToken: null, needsRefresh: true, invalidGrant: true };
    }
    // 网络类错误，暂时还能用旧 token
    refreshFailureAt.set(sessionId, now);
    return { accessToken: session.accessToken, needsRefresh: true };
  } finally {
    session.refreshing = false;
  }
}
