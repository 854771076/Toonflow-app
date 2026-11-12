import * as gatewayAuth from "@/utils/gatewayAuth";

export interface GatewayModelEntry {
  id: string;
  label: string;
  type: "text" | "image" | "video";
}

let gatewayModelsCache: { sub: string; expiresAt: number; models: GatewayModelEntry[] } | undefined;

export async function getGatewayModels(): Promise<GatewayModelEntry[]> {
  const sessionId = gatewayAuth.currentGatewaySessionId();
  const session = sessionId ? gatewayAuth.getSession(sessionId) : undefined;
  if (!session) throw Object.assign(new Error("登录已失效，请重新登录"), { status: 401 });

  const cached = gatewayModelsCache;
  if (cached && cached.sub === session.sub && cached.expiresAt > Date.now()) return cached.models;

  const res = await gatewayAuth.gatewayApiFetch("/v1/models");
  if (!res.ok) throw Object.assign(new Error("获取网关模型列表失败"), { status: res.status === 401 ? 401 : 502 });
  const body = (await res.json()) as { data?: { id?: unknown; display_name?: unknown; supported_endpoint_types?: unknown }[] };
  const models = (Array.isArray(body.data) ? body.data : []).flatMap(item => {
    const id = typeof item?.id === "string" ? item.id.trim() : "";
    if (!id) return [];
    const label = typeof item.display_name === "string" && item.display_name.trim() ? item.display_name.trim() : id;
    const endpointTypes = Array.isArray(item.supported_endpoint_types)
      ? item.supported_endpoint_types.filter((value): value is string => typeof value === "string")
      : [];
    const type = endpointTypes.includes("image-generation") ? "image" as const
      : endpointTypes.includes("openai-video") ? "video" as const
        : "text" as const;
    return [{ id, label, type }];
  });

  gatewayModelsCache = { sub: session.sub, expiresAt: Date.now() + 5 * 60 * 1000, models };
  return models;
}
