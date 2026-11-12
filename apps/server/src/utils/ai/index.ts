import { openAICompletionsApi } from "@earendil-works/pi-ai/api/openai-completions.lazy";
import { openAIResponsesApi } from "@earendil-works/pi-ai/api/openai-responses.lazy";
import { anthropicMessagesApi } from "@earendil-works/pi-ai/api/anthropic-messages.lazy";
import type { AssistantMessage, Context, Model } from "@earendil-works/pi-ai";
import { z } from "zod";
import { readReference } from "@/utils/media/generation";
import { createFileTransport, getUnsupportedFileText, type FileProvider } from "@/utils/ai/files";
import { getRequestFiles } from "@/utils/ai/requestFiles";
import { getWorkspaceStore } from "@/utils/storage";
import { getReadableFileMimeType } from "@/lib/documentFormats";
import { readDocument } from "@/utils/documents";
import { getConfiguredProviders, getModelLimits, getModelReasoning, getProviderBaseUrl, providerSchema } from "@/utils/ai/provider";
import { createBillingUsageTracker } from "@/utils/ai/billingUsage";
import * as gatewayAuth from "@/utils/gatewayAuth";
import { getGatewayModels } from "@/utils/ai/gatewayModels";

export { fetchProviderModels } from "@/utils/ai/models";
export { getConfiguredProviders, getModelLimits, getModelReasoning, providerSchema, reasoningEffortsSchema } from "@/utils/ai/provider";

const gatewayProviderId = "gateway";
const gatewayProviderLabel = "YuYuer Drama 网关";

async function getGatewayModel(modelId: string) {
  const models = await getGatewayModels();
  const target = models.find(item => item.id === modelId);
  if (!target) throw Object.assign(new Error("所选模型不存在，请重新选择"), { status: 400 });

  // 网关模型没有能力元数据，统一关闭推理档位，避免向不支持的上游发送推理参数。
  const model = { id: target.id, label: target.label, reasoningEfforts: false as const };
  const provider = providerSchema.parse({
    apiUrl: gatewayAuth.getConfig().baseUrl,
    apiKey: await gatewayAuth.getAccessToken(),
    protocol: "openai-completions",
    models: [model],
  });
  const limits = getModelLimits(gatewayProviderId, model);
  return {
    provider,
    model: { ...model, ...getModelReasoning(gatewayProviderId, model, provider.protocol), contextWindow: limits.contextWindow, maxOutputTokens: limits.maxTokens },
    baseUrl: getProviderBaseUrl(provider.apiUrl, provider.protocol),
  };
}

export async function getConfiguredModel(providerId: string, modelId: string) {
  if (providerId === gatewayProviderId) return getGatewayModel(modelId);
  const parsed = providerSchema.safeParse(getConfiguredProviders().find(item => item?.id === providerId));
  if (!parsed.success) throw Object.assign(new Error("请先在设置中配置模型供应商"), { status: 400 });
  const provider = parsed.data;
  const model = provider.models.find(item => item.id === modelId);
  if (!model) throw Object.assign(new Error("所选模型不存在，请重新选择"), { status: 400 });
  const baseUrl = getProviderBaseUrl(provider.apiUrl, provider.protocol);
  const limits = getModelLimits(providerId, model);
  return {
    provider,
    model: { ...model, ...getModelReasoning(providerId, model, provider.protocol), contextWindow: limits.contextWindow, maxOutputTokens: limits.maxTokens },
    baseUrl,
  };
}

export type ConfiguredModel = Awaited<ReturnType<typeof getConfiguredModel>>;

export async function listAiModels() {
  if (gatewayAuth.currentGatewaySessionId()) {
    const models = await getGatewayModels();
    return models.filter(entry => entry.type === "text").map(entry => {
      const model = { id: entry.id, label: entry.label, reasoningEfforts: false as const };
      const limits = getModelLimits(gatewayProviderId, model);
      return {
        providerId: gatewayProviderId, providerLabel: gatewayProviderLabel, protocol: "openai-completions" as const,
        modelId: entry.id, label: entry.label,
        contextWindow: limits.contextWindow, maxOutputTokens: limits.maxTokens,
        reasoningLevels: [] as string[],
      };
    });
  }

  return getConfiguredProviders().flatMap(item => {
    const parsed = providerSchema.extend({ id: z.string().min(1), label: z.string() }).safeParse(item);
    if (!parsed.success) return [];
    const provider = parsed.data;
    return provider.models.filter(model => model.id.trim()).map(model => {
      const limits = getModelLimits(provider.id, model);
      return {
        providerId: provider.id, providerLabel: provider.label, protocol: provider.protocol, modelId: model.id, label: model.label,
        contextWindow: limits.contextWindow, maxOutputTokens: limits.maxTokens,
        reasoningLevels: getModelReasoning(provider.id, model, provider.protocol).reasoningLevels,
      };
    });
  });
}

export function publicAiMessage(_configured: ConfiguredModel, message: AssistantMessage, _usageKnown = true) {
  return message;
}

const aiApis = {
  "openai-completions": openAICompletionsApi(),
  "openai-responses": openAIResponsesApi(),
  "anthropic-messages": anthropicMessagesApi(),
};

export const aiReferenceSchema = z.discriminatedUnion("dataType", [
  z.object({ dataType: z.literal("STRING"), value: z.string().max(1000000) }),
  z.object({ dataType: z.literal("IMAGE"), value: z.object({ url: z.string().min(1).max(4096), mimeType: z.string().startsWith("image/") }) }),
  z.object({ dataType: z.literal("VIDEO"), value: z.object({ url: z.string().min(1).max(4096), mimeType: z.string().startsWith("video/") }) }),
  z.object({ dataType: z.literal("FILE"), value: z.object({ url: z.string().min(1).max(4096), mimeType: z.string().min(1).max(128) }) }),
]);

export async function readAiReferences(
  directory: string | undefined,
  references: z.infer<typeof aiReferenceSchema>[],
  signal?: AbortSignal,
  provider?: FileProvider,
) {
  return Promise.all(references.map(async (item) => {
    signal?.throwIfAborted();
    if (item.dataType === "STRING") return { dataType: item.dataType, value: item.value };
    if (!directory) throw Object.assign(new Error("文件参考需要工作目录"), { status: 400 });
    if (item.dataType === "FILE") {
      if (!getReadableFileMimeType(item.value.url, item.value.mimeType)) throw Object.assign(new Error("不支持此参考文件格式"), { status: 400 });
      const store = getWorkspaceStore();
      const info = await store.stat(directory, item.value.url);
      if (info.type !== "file" || info.size > 100 * 1024 * 1024) throw Object.assign(new Error("参考文档须为不超过 100 MB 的文件"), { status: 400 });
      const bytes = await store.read(directory, item.value.url);
      signal?.throwIfAborted();
      const content = await readDocument(item.value.url, Buffer.from(bytes.buffer, bytes.byteOffset, bytes.byteLength), item.value.mimeType);
      signal?.throwIfAborted();
      return { dataType: "STRING" as const, value: `参考文档：${item.value.url}\n${content.toString("utf8")}` };
    }
    const unsupported = provider && getUnsupportedFileText(provider, { path: item.value.url, mimeType: item.value.mimeType });
    if (unsupported) return { dataType: "STRING" as const, value: unsupported };
    const media = await readReference(directory, { path: item.value.url, mimeType: item.value.mimeType }, item.dataType.toLowerCase(), signal);
    return { dataType: item.dataType, value: `data:${media.mimeType};base64,${media.data}` };
  }));
}

export function referenceContent(protocol: string, prompt: string, references: Awaited<ReturnType<typeof readAiReferences>>, referenceOffset = 0) {
  const textPart = (text: string) => ({ type: protocol === "openai-responses" ? "input_text" : "text", text });
  const content: object[] = [textPart(prompt)];
  references.forEach((item, index) => {
    content.push(textPart(`{{ref ${referenceOffset + index + 1}}}${item.dataType === "STRING" ? `\n${item.value}` : ""}`));
    if (item.dataType === "STRING") return;
    if (protocol === "openai-completions") {
      content.push(item.dataType === "IMAGE"
        ? { type: "image_url", image_url: { url: item.value } }
        : { type: "video_url", video_url: { url: item.value } });
    } else if (protocol === "openai-responses") {
      const extension = item.value.slice(11, item.value.indexOf(";")).replace("quicktime", "mov");
      content.push(item.dataType === "IMAGE"
        ? { type: "input_image", image_url: item.value, detail: "auto" }
        : { type: "input_file", filename: `reference${referenceOffset + index + 1}.${extension}`, file_data: item.value });
    } else {
      const separator = item.value.indexOf(",");
      content.push({
        type: item.dataType === "IMAGE" ? "image" : "document",
        source: { type: "base64", media_type: item.value.slice(5, item.value.indexOf(";")), data: item.value.slice(separator + 1) },
      });
    }
  });
  return content;
}

export function streamAi(
  configured: ConfiguredModel,
  context: Context,
  signal: AbortSignal,
  references: Awaited<ReturnType<typeof readAiReferences>> = [],
) {
  const { provider, model: configuredModel, baseUrl } = configured;
  const model: Model<typeof provider.protocol> = {
    id: configuredModel.id, name: configuredModel.label, provider: "toonflow", api: provider.protocol, baseUrl,
    reasoning: false, input: ["text", "image"],
    cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
    contextWindow: configuredModel.contextWindow,
    maxTokens: configuredModel.maxOutputTokens,
  };
  const usageTracker = createBillingUsageTracker(provider.protocol);
  const files = createFileTransport({ ...provider, apiUrl: baseUrl }, { signal });
  const stream = aiApis[provider.protocol].streamSimple(model, context, {
    apiKey: provider.apiKey,
    headers: provider.headers,
    signal,
    maxRetries: 3,
    fetch: files.fetch,
    onPayload: async (payload) => {
      let body = payload as Record<string, unknown>;
      if (references.length) {
        const field = provider.protocol === "openai-responses" ? "input" : "messages";
        const messages = body[field] as { role: string; content: unknown }[];
        // ACT: 后续 Anthropic 工具结果也使用 user 角色，附件只补充到最初的输入。
        const firstUser = messages.findIndex(message => message.role === "user");
        const attachmentContent = referenceContent(provider.protocol, "", references).slice(1);
        body = { ...body, [field]: messages.map((message, index) => index === firstUser
          ? { ...message, content: [
            ...(Array.isArray(message.content) ? message.content : referenceContent(provider.protocol, String(message.content ?? ""), [])),
            ...attachmentContent,
          ] }
          : message) };
      }
      await files.prepare(body);
      const imageBytes = getRequestFiles(body).filter(file => file.mimeType.toLowerCase().startsWith("image/")).reduce((sum, file) => sum + file.inlineBytes, 0);
      if (imageBytes > (provider.maxRequestImageBytes ?? 20 * 1024 * 1024)
        || Buffer.byteLength(JSON.stringify(body), "utf8") > (provider.maxRequestBytes ?? 32 * 1024 * 1024)) {
        throw new Error("模型请求超过附件或请求体字节预算，请减少附件或上下文后重试");
      }
      return body;
    },
  });
  return Object.assign(stream, {
    billingUsage: usageTracker.usage,
    upstreamSubmitted: usageTracker.submitted,
    upstreamRejected: usageTracker.rejected,
  });
}
