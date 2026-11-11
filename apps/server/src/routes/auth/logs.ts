import { Router } from "express";
import { z } from "zod";
import { validateFields } from "@/lib/middleware";
import { success } from "@/lib/responseFormat";
import * as g from "@/utils/gatewayAuth";

const router = Router();

const querySchema = {
  page: z.coerce.number().int().min(1).max(10000).optional(),
  pageSize: z.coerce.number().int().min(1).max(100).optional(),
};

// 代理 new-api /oauth/logs，网关已做字段白名单，不会返回 prompt 原文与密钥。
router.get("/", validateFields(querySchema, "query"), async (req, res) => {
  const page = Number(req.query.page) || 1;
  const pageSize = Number(req.query.pageSize) || 20;

  const upstream = await g.gatewayApiFetch(`/oauth/logs?page=${page}&page_size=${pageSize}`);
  if (!upstream.ok) {
    throw Object.assign(new Error("获取用量日志失败"), { status: upstream.status === 401 ? 401 : 502 });
  }

  const body = (await upstream.json()) as { total?: number; page?: number; page_size?: number; items?: unknown[] };
  res.json(success({
    total: body.total ?? 0,
    page: body.page ?? page,
    pageSize: body.page_size ?? pageSize,
    items: body.items ?? [],
  }));
});

export default router;
