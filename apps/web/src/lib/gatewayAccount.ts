import http from "@/lib/http";

export interface GatewayQuota {
  appQuota: number;
  appUsedQuota: number;
  quota: number;
  usedQuota: number;
  requestCount: number;
  group: string;
  quotaPerUnit: number;
  displayType: string;
  usdExchangeRate: number;
}

export interface GatewayUsageLog {
  id: number;
  created_at: number;
  model_name: string;
  prompt_tokens: number;
  completion_tokens: number;
  quota: number;
  use_time: number;
}

export interface GatewayUsagePage {
  total: number;
  page: number;
  pageSize: number;
  items: GatewayUsageLog[];
}

export type GatewayPaymentMethod = "balance" | "waffo_pancake";

export type GatewayCheckout =
  | { status: "success"; creditedQuota: number }
  | { status: "pending"; checkoutUrl: string; orderId: string; expiresAt: string };

export function fetchGatewayQuota() {
  return http<GatewayQuota>({ url: "/api/auth/quota", method: "GET" });
}

export function fetchGatewayLogs(page: number, pageSize: number) {
  return http<GatewayUsagePage>({ url: "/api/auth/logs", method: "GET", params: { page, pageSize } });
}

export function createGatewayCheckout(amount: number, paymentMethod: GatewayPaymentMethod) {
  return http<GatewayCheckout>({ url: "/api/billing/checkout", method: "POST", data: { amount, paymentMethod } });
}

// 额度换算只在这里做一次，避免各页面重复折算。
export function formatQuota(value: number, info: Pick<GatewayQuota, "quotaPerUnit" | "displayType" | "usdExchangeRate">) {
  if (info.displayType === "TOKENS") return `${value.toLocaleString()} tokens`;
  const unit = info.quotaPerUnit || 500000;
  const rate = info.displayType === "CNY" ? info.usdExchangeRate || 1 : 1;
  const symbol = info.displayType === "CNY" ? "¥" : info.displayType === "USD" ? "$" : "";
  return `${symbol}${((value / unit) * rate).toFixed(2)}`;
}
