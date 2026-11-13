import { Router } from "express";
import { randomUUID } from "node:crypto";
import { z } from "zod";
import { validateFields } from "@/lib/middleware";
import { success } from "@/lib/responseFormat";
import * as g from "@/utils/gatewayAuth";

const router = Router();

const bodySchema = {
  accessToken: z.string().min(1),
  refreshToken: z.string().optional(),
};

// 前端（Web/Flutter）用 Supabase signInWithOAuth 登录后，把 provider_token 交给后端建立 session。
// 后端用 accessToken 调 /oauth/userinfo 解析 sub（new-api 用户 id），沿用 saas/<sub>/ 工作区隔离。
router.post("/", validateFields(bodySchema), async (req, res) => {
  const { accessToken, refreshToken } = req.body as { accessToken: string; refreshToken?: string };

  const userinfo = await g.fetchUserinfo(accessToken.trim());

  const sessionId = randomUUID();
  g.createSession(sessionId, {
    access_token: accessToken.trim(),
    token_type: "Bearer",
    // provider_token 是 new-api access token，TTL 默认 1 小时；有 refresh_token 时由 getOrRefreshAccessToken 自动续期。
    expires_in: 3600,
    refresh_token: refreshToken?.trim() || undefined,
  }, userinfo);

  res.cookie("gateway_session", sessionId, {
    httpOnly: true,
    secure: process.env.NODE_ENV === "production",
    sameSite: "lax",
    path: "/",
    maxAge: 7 * 24 * 60 * 60 * 1000,
  });
  // sessionId 一并返回：Web 走 HttpOnly cookie，Flutter 无浏览器 cookie，需从响应体取。
  res.json(success({ sub: userinfo.sub, username: userinfo.username, email: userinfo.email, sessionId }));
});

export default router;
