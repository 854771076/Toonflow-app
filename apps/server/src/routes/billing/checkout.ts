import { Router } from "express";
import { z } from "zod";
import { validateFields } from "@/lib/middleware";
import { success } from "@/lib/responseFormat";
import * as g from "@/utils/gatewayAuth";

const router = Router();

const bodySchema = {
  amount: z.number().int().positive().max(1000000),
  paymentMethod: z.enum(["balance", "waffo_pancake"]).default("waffo_pancake"),
};

// 代理 new-api /oauth/topup/checkout：balance 为平台余额到 App 池的同步划转，
// waffo_pancake 返回 checkout_url，前端只在 iframe 中打开。
router.post("/", validateFields(bodySchema), async (req, res) => {
  const { amount, paymentMethod } = req.body as z.infer<z.ZodObject<typeof bodySchema>>;
  const upstream = await g.gatewayApiFetch("/oauth/topup/checkout", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ amount, payment_method: paymentMethod }),
  });

  const payload = (await upstream.json().catch(() => ({}))) as {
    status?: string;
    quota?: number;
    checkout_url?: string;
    order_id?: string;
    expires_at?: string;
    error_description?: string;
  };

  if (!upstream.ok) {
    const status = upstream.status === 401 ? 401 : upstream.status >= 500 ? 502 : 400;
    throw Object.assign(new Error(payload.error_description ?? "创建充值订单失败"), { status });
  }

  if (payload.status === "success") {
    // balance 划转同步完成，quota 为本次划入 App 池的额度（非余额）。
    res.json(success({ status: "success", creditedQuota: payload.quota ?? 0 }));
    return;
  }

  if (!payload.checkout_url) {
    throw Object.assign(new Error(payload.error_description ?? "创建充值订单失败"), { status: 502 });
  }

  res.json(success({
    status: "pending",
    checkoutUrl: payload.checkout_url,
    orderId: payload.order_id ?? "",
    expiresAt: payload.expires_at ?? "",
  }));
});

export default router;
