import { Router } from "express";
import * as g from "@/utils/gatewayAuth";

const router = Router();

router.get("/", (req, res) => {
  const sessionId = req.cookies?.gateway_session;
  const session = sessionId ? g.getSession(sessionId) : undefined;

  if (!session) {
    res.json({ code: 200, data: { authenticated: false }, message: "成功" });
    return;
  }

  res.json({
    code: 200,
    data: {
      authenticated: true,
      sub: session.sub,
      username: session.username,
      email: session.email,
    },
    message: "成功",
  });
});

export default router;
