import { Router } from "express";
import { z } from "zod";
import u from "@/utils";
import { validateFields } from "@/lib/middleware";
import { success } from "@/lib/responseFormat";

const router = Router();

export default router.delete("/", validateFields({ directory: z.string().min(1).max(4096), path: z.string().max(4096), recursive: z.boolean().optional() }), async (req, res) => {
  if (!req.body.path || !req.body.path.split(/[\\/]/).some((part: string) => part && part !== ".")) {
    throw Object.assign(new Error("不能修改工作区根目录"), { status: 400 });
  }
  const store = u.storage.getWorkspaceStore();
  const workspace = await store.resolveWorkspace(req, req.body.directory);
  await store.remove(workspace, req.body.path, req.body.recursive === true);
  res.json(success());
});
