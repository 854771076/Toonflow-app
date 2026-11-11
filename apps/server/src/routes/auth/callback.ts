import { Router } from "express";
import * as g from "@/utils/gatewayAuth";

const router = Router();

router.get("/", async (req, res) => {
  const query = req.query as { code?: string; state?: string };
  const code = query.code;
  const queryState = query.state;

  if (!code || !queryState) {
    res.status(400).json({ code: 400, data: null, message: "缺少 code 或 state" });
    return;
  }

  const cookieState = req.cookies?.gateway_state;
  const cookieVerifier = req.cookies?.gateway_code_verifier;

  if (!cookieState || !cookieVerifier) {
    res.status(400).json({ code: 400, data: null, message: "缺少临时 cookie，可能浏览器限制了跨站 cookie" });
    return;
  }

  if (queryState !== cookieState) {
    res.status(403).json({ code: 403, data: null, message: "state 不匹配，可能是 CSRF" });
    return;
  }

  let cfg: g.GatewayConfig;
  try {
    cfg = g.getConfig();
  } catch {
    res.status(503).json({ code: 503, data: null, message: "OAuth gateway 未配置" });
    return;
  }

  const redirectUri = `${cfg.appPublicUrl}/api/auth/callback`;

  try {
    const tokens = await g.exchangeCode({
      code,
      redirectUri,
      clientId: cfg.clientId,
      codeVerifier: cookieVerifier,
    });

    const userinfo = await g.fetchUserinfo(tokens.access_token);

    const sessionId = crypto.randomUUID();
    g.createSession(sessionId, tokens, userinfo);

    const cookieOptions = {
      httpOnly: true,
      secure: process.env.NODE_ENV === "production",
      sameSite: "lax" as const,
      path: "/",
      maxAge: 7 * 24 * 60 * 60 * 1000, // Express maxAge 单位为毫秒，7 天
    };

    res.cookie("gateway_session", sessionId, cookieOptions);
    res.clearCookie("gateway_state", { path: "/api/auth/callback" });
    res.clearCookie("gateway_code_verifier", { path: "/api/auth/callback" });

    res.redirect(302, "/");
  } catch {
    res.clearCookie("gateway_state", { path: "/api/auth/callback" });
    res.clearCookie("gateway_code_verifier", { path: "/api/auth/callback" });
    res.status(400).json({ code: 400, data: null, message: "OAuth 回调失败" });
  }
});

export default router;
