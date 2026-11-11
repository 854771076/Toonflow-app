import { Router } from "express";
import { success } from "@/lib/responseFormat";
import * as g from "@/utils/gatewayAuth";

const router = Router();

// 代理 new-api /oauth/userinfo，只向前端暴露额度相关字段，不下发 access token。
router.get("/", async (_req, res) => {
  const upstream = await g.gatewayApiFetch("/oauth/userinfo");
  if (!upstream.ok) {
    throw Object.assign(new Error("获取账户额度失败"), { status: upstream.status === 401 ? 401 : 502 });
  }
  const info = (await upstream.json()) as {
    quota?: number;
    used_quota?: number;
    app_quota?: number;
    app_used_quota?: number;
    request_count?: number;
    group?: string;
  };
  const status = await g.getGatewayStatus();
  res.json(success({
    // App 池是本应用 token relay 的实际扣费池；平台 quota 仅用于 balance 划转来源。
    appQuota: info.app_quota ?? 0,
    appUsedQuota: info.app_used_quota ?? 0,
    quota: info.quota ?? 0,
    usedQuota: info.used_quota ?? 0,
    requestCount: info.request_count ?? 0,
    group: info.group ?? "",
    quotaPerUnit: status.quotaPerUnit,
    displayType: status.displayType,
    usdExchangeRate: status.usdExchangeRate,
  }));
});

export default router;
