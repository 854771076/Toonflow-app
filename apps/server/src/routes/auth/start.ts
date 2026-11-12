import { Router } from "express";
import * as g from "@/utils/gatewayAuth";

const router = Router();

router.get("/", (req, res) => {
  let cfg: g.GatewayConfig;
  try {
    cfg = g.getConfig();
  } catch {
    res.status(503).json({ code: 503, data: null, message: "OAuth gateway 未配置" });
    return;
  }

  if (!cfg.appPublicUrl) {
    res.status(503).json({ code: 503, data: null, message: "APP_PUBLIC_URL 未配置" });
    return;
  }

  const codeVerifier = g.generateCodeVerifier();
  const state = g.generateState();
  const codeChallenge = g.computeCodeChallenge(codeVerifier);
  const redirectUri = g.resolveRedirectUri(req);

  const authorizeUrl = g.buildAuthorizeUrl({
    clientId: cfg.clientId,
    redirectUri,
    state,
    codeChallenge,
    scopes: cfg.scopes,
  });

  const cookieOptions = {
    httpOnly: true,
    secure: process.env.NODE_ENV === "production",
    sameSite: "lax" as const,
    path: "/api/auth/callback",
    maxAge: 5 * 60 * 1000, // Express maxAge 单位为毫秒，5 分钟足够完成授权
  };

  res.cookie("gateway_code_verifier", codeVerifier, cookieOptions);
  res.cookie("gateway_state", state, cookieOptions);

  res.redirect(302, authorizeUrl);
});

export default router;
