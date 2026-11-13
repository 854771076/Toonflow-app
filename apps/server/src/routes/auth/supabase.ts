import { Router } from "express";
import u from "@/utils";
import { success } from "@/lib/responseFormat";

const router = Router();

// 移动端登录前读取 Supabase 公开配置（publishable key 本就公开，无需鉴权）。
router.get("/", (req, res) => {
  const settings = u.conf.get("settings", {}) as { supabaseUrl?: unknown; supabaseAnonKey?: unknown };
  res.set("Cache-Control", "no-store");
  res.json(success({
    supabaseUrl: typeof settings.supabaseUrl === "string" ? settings.supabaseUrl : "",
    supabaseAnonKey: typeof settings.supabaseAnonKey === "string" ? settings.supabaseAnonKey : "",
  }));
});

export default router;
