import { Router, type Response as ExpressResponse } from "express";
import { z } from "zod";
import type { Context, Message } from "@earendil-works/pi-ai";
import { validateFields } from "@/lib/middleware";
import u from "@/utils";
import * as gatewayAuth from "@/utils/gatewayAuth";
import { translateError, translateMessage, validationOptions } from "@/lib/i18n";

const textPart = z.object({ type: z.literal("text"), text: z.string(), textSignature: z.string().optional() });
const imagePart = z.object({ type: z.literal("image"), data: z.string(), mimeType: z.string().startsWith("image/") });
const messageSchema: z.ZodType<Message> = z.discriminatedUnion("role", [
  z.object({
    role: z.literal("user"), content: z.union([z.string(), z.array(z.union([textPart, imagePart])).max(1000)]),
    timestamp: z.number().nonnegative(),
  }),
  z.looseObject({
    role: z.literal("assistant"),
    content: z.array(z.discriminatedUnion("type", [
      textPart,
      z.object({ type: z.literal("thinking"), thinking: z.string(), thinkingSignature: z.string().optional(), redacted: z.boolean().optional() }),
      z.object({
        type: z.literal("toolCall"), id: z.string().min(1), name: z.string().min(1), arguments: z.record(z.string(), z.json()),
        thoughtSignature: z.string().optional(), namespace: z.string().optional(),
      }),
    ])).max(1000),
    api: z.string().min(1), provider: z.string().min(1), model: z.string().min(1), timestamp: z.number().nonnegative(),
    stopReason: z.enum(["pending", "stop", "length", "toolUse", "error", "aborted", "deferred"]),
    usage: z.looseObject({
      input: z.number().nonnegative(), output: z.number().nonnegative(), cacheRead: z.number().nonnegative(), cacheWrite: z.number().nonnegative(),
      totalTokens: z.number().nonnegative(),
      cost: z.object({ input: z.number(), output: z.number(), cacheRead: z.number(), cacheWrite: z.number(), total: z.number() }),
    }),
  }),
  z.looseObject({
    role: z.literal("toolResult"), toolCallId: z.string().min(1), toolName: z.string().min(1),
    content: z.array(z.union([textPart, imagePart])).max(1000), isError: z.boolean(), timestamp: z.number().nonnegative(),
  }),
]);

const contextSchema: z.ZodType<Context> = z.object({
  systemPrompt: z.string().max(100000).optional(),
  messages: z.array(messageSchema).min(1).max(2000),
  tools: z.array(z.object({
    name: z.string().regex(/^[a-z][a-zA-Z0-9]{0,63}$/),
    description: z.string().min(1).max(10000),
    parameters: z.record(z.string(), z.json()).refine(value => value.type === "object" && JSON.stringify(value).length <= 100000, "工具参数必须是 JSON 对象结构，且不超过 100 KB"),
    constrainedSampling: z.union([
      z.literal(false),
      z.object({ type: z.literal("json_schema"), strict: z.enum(["prefer", "require"]) }),
      z.object({ type: z.literal("grammar"), variants: z.object({ openai_lark: z.string().optional(), openai_regex: z.string().optional() }) }),
    ]).optional(),
  })).max(32).refine(tools => new Set(tools.map(tool => tool.name)).size === tools.length, "工具名称不能重复").optional(),
}).refine(context => Buffer.byteLength(JSON.stringify(context)) <= 8000000, "模型上下文不能超过 8 MB");

const inputSchema = z.object({
  providerId: z.string().min(1), modelId: z.string().min(1),
  requestId: z.uuid().optional(),
  context: contextSchema,
  directory: z.string().min(1).max(4096).optional(),
  references: z.array(u.ai.aiReferenceSchema).max(32).optional(),
});

function toGatewayMessages(ctx: Context): unknown[] {
  const result: unknown[] = [];
  if (ctx.systemPrompt) {
    result.push({ role: "system", content: ctx.systemPrompt });
  }
  for (const msg of ctx.messages) {
    if (msg.role === "user") {
      result.push({ role: "user", content: msg.content });
    } else if (msg.role === "assistant") {
      // ACT: thinking part 暂时丢弃；toolCall 累积后在 done 事件里体现
      const textParts: string[] = [];
      const toolCalls: unknown[] = [];
      for (const part of msg.content) {
        if (part.type === "text") textParts.push(part.text);
        else if (part.type === "toolCall") {
          toolCalls.push({
            id: part.id,
            type: "function",
            function: { name: part.name, arguments: JSON.stringify(part.arguments) },
          });
        }
      }
      const content = textParts.join("");
      result.push({
        role: "assistant",
        content: content || null,
        ...(toolCalls.length > 0 ? { tool_calls: toolCalls } : {}),
      });
    } else if (msg.role === "toolResult") {
      const text = msg.content.map(p => p.type === "text" ? p.text : "").join("");
      result.push({ role: "tool", tool_call_id: msg.toolCallId, content: text });
    }
  }
  return result;
}

async function relayToGateway(
  sessionId: string,
  input: z.infer<typeof inputSchema>,
  res: ExpressResponse,
): Promise<void> {
  // 1. 获取 OAuth token
  const tokenResult = await gatewayAuth.getOrRefreshAccessToken(sessionId);
  if (tokenResult.invalidGrant) {
    res.clearCookie("gateway_session");
    res.status(401).json({ code: 401, message: "会话已过期" });
    return;
  }
  if (!tokenResult.accessToken) {
    res.status(401).json({ code: 401, message: "未授权" });
    return;
  }

  // 2. 构造 new-api chat/completions body
  const body: Record<string, unknown> = {
    model: input.modelId,
    messages: toGatewayMessages(input.context),
    stream: true,
  };
  if (input.context.tools?.length) body.tools = input.context.tools;

  // 3. 转发到 gateway new-api，401 时刷新 token 重试一次
  const cfg = gatewayAuth.getConfig();
  const upstream = await fetchUpstream(cfg.baseUrl, body, tokenResult.accessToken);
  if (!upstream) return;

  async function fetchUpstream(baseUrl: string, requestBody: Record<string, unknown>, accessToken: string): Promise<Response | null> {
    const first = await fetch(`${baseUrl}/v1/chat/completions`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(requestBody),
    });

    if (first.status !== 401) return first;

    // upstream 401 → 尝试刷新 token 重试一次
    const refreshed = await gatewayAuth.getOrRefreshAccessToken(sessionId);
    if (refreshed.invalidGrant || !refreshed.accessToken) {
      // 彻底失效 → 清 cookie，强制登出；注意此时还没 flush headers，直接返回 401 JSON
      res.clearCookie("gateway_session", { path: "/" });
      gatewayAuth.deleteSession(sessionId);
      res.status(401).json({ type: "error", message: "登录已过期，请重新登录" });
      return null;
    }

    // 刷新成功，用新 token 重试一次
    const retry = await fetch(`${baseUrl}/v1/chat/completions`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${refreshed.accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(requestBody),
    });

    // 重试还是 401 → 彻底放弃
    if (retry.status === 401) {
      res.clearCookie("gateway_session", { path: "/" });
      gatewayAuth.deleteSession(sessionId);
      res.status(401).json({ type: "error", message: "登录已过期，请重新登录" });
      return null;
    }

    return retry;
  }

  // 上游非 200 → 转错误给客户端
  if (!upstream.ok || !upstream.body) {
    const errText = !upstream.ok ? await upstream.text() : "上游无响应体";
    res.set({
      "Content-Type": "text/event-stream; charset=utf-8",
      "Cache-Control": "no-cache, no-transform",
      "X-Accel-Buffering": "no",
    });
    res.flushHeaders();
    res.write(`data: ${JSON.stringify({ type: "error", message: errText })}\n\n`);
    res.end();
    return;
  }

  // 4. 建立 SSE 流并转发
  res.set({
    "Content-Type": "text/event-stream; charset=utf-8",
    "Cache-Control": "no-cache, no-transform",
    "X-Accel-Buffering": "no",
  });
  res.flushHeaders();

  let clientClosed = false;
  let heartbeat: ReturnType<typeof setInterval> | undefined;
  const close = () => {
    clientClosed = true;
    clearInterval(heartbeat);
  };
  res.once("close", close);
  res.once("finish", close);
  res.once("error", close);

  heartbeat = setInterval(() => {
    if (!clientClosed && !res.writableNeedDrain) res.write(": keepalive\n\n");
  }, 20000);

  let fullText = "";
  let stopReason: string | undefined;
  let usage: { input?: number; output?: number; totalTokens?: number } | undefined;

  const write = (chunk: string) => {
    if (clientClosed || res.destroyed || res.writableEnded) return;
    try { res.write(chunk); } catch { close(); }
  };
  const send = (event: object) => write(`data: ${JSON.stringify(event)}\n\n`);

  try {
    const reader = upstream.body.getReader();
    const decoder = new TextDecoder();
    let buffer = "";

    while (true) {
      if (clientClosed) break;
      const { done, value } = await reader.read();
      if (done) break;
      buffer += decoder.decode(value, { stream: true });

      // 按 SSE 事件分隔符 \n\n 切分
      let sepIdx: number;
      while ((sepIdx = buffer.indexOf("\n\n")) !== -1) {
        const rawEvent = buffer.slice(0, sepIdx);
        buffer = buffer.slice(sepIdx + 2);

        for (const line of rawEvent.split("\n")) {
          if (!line.startsWith("data:")) continue;
          const data = line.slice(5).trim();
          if (data === "[DONE]") continue;

          let parsed: Record<string, unknown>;
          try {
            parsed = JSON.parse(data) as Record<string, unknown>;
          } catch {
            continue;
          }

          const choices = parsed.choices as Array<Record<string, unknown>> | undefined;
          const delta = choices?.[0]?.delta as Record<string, unknown> | undefined;
          if (typeof delta?.content === "string") {
            fullText += delta.content;
            send({ type: "text", delta: delta.content });
          }

          const finishReason = choices?.[0]?.finish_reason as string | undefined;
          if (finishReason) {
            stopReason = finishReason === "stop" ? "stop"
              : finishReason === "length" ? "length"
              : finishReason === "tool_calls" ? "toolUse"
              : finishReason;
          }

          const rawUsage = parsed.usage as Record<string, unknown> | undefined;
          if (rawUsage) {
            usage = {
              input: rawUsage.input_tokens as number | undefined,
              output: rawUsage.output_tokens as number | undefined,
              totalTokens: rawUsage.total_tokens as number | undefined,
            };
          }
        }
      }
    }

    // ACT: 本轮简化——tool_calls delta 累积后在 done 事件里不体现，客户端仍能拿到 text 和 stopReason
    send({
      type: "done",
      message: {
        role: "assistant",
        content: [{ type: "text", text: fullText }],
        stopReason: stopReason ?? "stop",
        usage: usage ?? { input: 0, output: 0, totalTokens: 0 },
      },
    });
  } catch (cause) {
    if (!res.headersSent) throw cause;
    if (!clientClosed) {
      send({ type: "error", message: cause instanceof Error ? cause.message : "转发失败" });
    }
  } finally {
    clearInterval(heartbeat);
    if (!res.destroyed && !res.writableEnded) res.end();
  }
}

export default Router().post("/", validateFields(inputSchema.shape), async (req, res) => {
  const sessionId = req.cookies?.gateway_session;
  if (sessionId) {
    // SaaS 模式：强制走 relay，不 fallback 到旧 provider 配置
    await relayToGateway(sessionId, inputSchema.parse(req.body, validationOptions()), res);
    return;
  }

  const input = inputSchema.parse(req.body, validationOptions());
  const configured = await u.ai.getConfiguredModel(input.providerId, input.modelId);
  const controller = new AbortController();
  let stream: ReturnType<typeof u.ai.streamAi> | undefined;
  let hasOutput = false;
  let clientClosed = false;
  let heartbeat: ReturnType<typeof setInterval> | undefined;
  const close = () => {
    clientClosed = true;
    clearInterval(heartbeat);
    controller.abort();
  };
  const write = (chunk: string) => {
    if (clientClosed || res.destroyed || res.writableEnded) return;
    try { res.write(chunk); } catch { close(); }
  };
  const send = (event: object) => write(`data: ${JSON.stringify(event)}\n\n`);
  res.once("close", close);
  req.once("aborted", close);
  req.socket.once("close", close);
  if (req.aborted || res.destroyed || req.socket.destroyed) close();
  try {
    const directory = input.references?.some(item => item.dataType !== "STRING")
      ? await u.storage.getWorkspaceStore().resolveWorkspace(req, input.directory ?? "") : undefined;
    const references = await u.ai.readAiReferences(directory, input.references ?? [], controller.signal, configured.provider);
    controller.signal.throwIfAborted();
    res.set({ "Content-Type": "text/event-stream; charset=utf-8", "Cache-Control": "no-cache, no-transform", "X-Accel-Buffering": "no" });
    res.flushHeaders();
    controller.signal.throwIfAborted();
    stream = u.ai.streamAi(configured, input.context, controller.signal, references);
    heartbeat = setInterval(() => {
      if (!res.writableNeedDrain) write(": keepalive\n\n");
    }, 20000);
    for await (const event of stream) {
      if (event.type === "text_delta" || event.type === "thinking_delta") {
        if (event.delta) hasOutput = true;
        send({ type: event.type === "text_delta" ? "text" : "reasoning", delta: event.delta });
      } else if (event.type === "toolcall_start" || event.type === "toolcall_delta" || event.type === "toolcall_end") {
        hasOutput = true;
      }
    }
    const message = await stream.result();
    hasOutput ||= message.content.some(part => part.type === "toolCall" || part.type === "text" && !!part.text || part.type === "thinking" && !!part.thinking);
    send({ type: "done", message: u.ai.publicAiMessage(configured, message) });
  } catch (cause) {
    if (!res.headersSent) throw cause;
    send({ type: "error", message: cause instanceof Error ? translateError(cause) : translateMessage("模型请求失败") });
  } finally {
    clearInterval(heartbeat);
    controller.abort();
    res.off("close", close);
    req.off("aborted", close);
    req.socket.off("close", close);
    if (!clientClosed && res.headersSent && !res.destroyed && !res.writableEnded) res.end();
  }
});
