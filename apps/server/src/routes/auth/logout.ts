import { Router } from "express";
import * as g from "@/utils/gatewayAuth";

const router = Router();

router.post("/", async (req, res) => {
  const sessionId = req.cookies?.gateway_session;

  if (sessionId) {
    const session = g.getSession(sessionId);
    if (session) {
      // best effort revoke
      const revokes: Promise<void>[] = [];
      if (session.accessToken) revokes.push(g.revokeToken(session.accessToken));
      if (session.refreshToken) revokes.push(g.revokeToken(session.refreshToken));
      await Promise.allSettled(revokes);
      g.deleteSession(sessionId);
    }
  }

  res.clearCookie("gateway_session", { path: "/" });
  res.json({ code: 200, data: { success: true }, message: "已登出" });
});

export default router;
