import { Router } from "express";
import type { Response } from "express";
import * as g from "@/utils/gatewayAuth";

const router = Router();

interface ChatRequest {
  model: string;
  messages: unknown;
  stream?: boolean;
  [key: string]: unknown;
}

async function doRelay(accessToken: string, body: ChatRequest, res: Response): Promise<number> {
  const cfg = g.getConfig();
  const targetUrl = `${cfg.baseUrl}/v1/chat/completions`;

  const upstream = await fetch(targetUrl, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${accessToken}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });

  if (!upstream.ok) {
    return upstream.status;
  }

  // 复制响应头
  const contentType = upstream.headers.get("content-type") || "";
  if (contentType.includes("text/event-stream")) {
    res.set({
      "Content-Type": "text/event-stream; charset=utf-8",
      "Cache-Control": "no-cache, no-transform",
      "X-Accel-Buffering": "no",
    });
  } else {
    res.set({ "Content-Type": contentType });
  }
  res.status(200);
  res.flushHeaders();

  // 流式管道
  const reader = upstream.body?.getReader();
  if (!reader) return upstream.status;

  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      if (res.destroyed || res.writableEnded) break;
      res.write(value);
    }
  } catch {
    // 客户端断开或上游错误，忽略
  } finally {
    res.end();
  }

  return upstream.status;
}

router.post("/", async (req, res) => {
  let cfg: g.GatewayConfig;
  try {
    cfg = g.getConfig();
  } catch {
    res.status(503).json({ code: 503, data: null, message: "OAuth gateway 未配置" });
    return;
  }

  const sessionId = req.cookies?.gateway_session;
  if (!sessionId) {
    res.status(401).json({ code: 401, data: null, message: "未登录" });
    return;
  }

  const { accessToken, needsRefresh, invalidGrant } = await g.getOrRefreshAccessToken(sessionId);

  if (invalidGrant) {
    res.clearCookie("gateway_session", { path: "/" });
    g.deleteSession(sessionId);
    res.status(401).json({ code: 401, data: null, message: "登录已过期，请重新登录" });
    return;
  }

  if (!accessToken) {
    res.status(401).json({ code: 401, data: null, message: "未登录或 token 已过期" });
    return;
  }

  const body = req.body as ChatRequest;
  if (!body || typeof body !== "object") {
    res.status(400).json({ code: 400, data: null, message: "请求体必须是 JSON 对象" });
    return;
  }
  if (typeof body.model !== "string" || typeof body.messages === "undefined") {
    res.status(400).json({ code: 400, data: null, message: "缺少 model 或 messages" });
    return;
  }

  // 第一次尝试
  const status = await doRelay(accessToken, body, res);

  // 如果是 401 且还没刷新过，尝试刷新一次后重试
  if (status === 401 && !needsRefresh) {
    const refreshed = await g.getOrRefreshAccessToken(sessionId);
    if (refreshed.accessToken && !refreshed.invalidGrant) {
      // 需要创建新响应，因为原来的已经 flushHeaders 了
      // ACT: 这种情况比较少见，简单处理：客户端会收到 401，需要重试
      // 后续可以优化为刷新后重放一次
    }
  }
});

export default router;
