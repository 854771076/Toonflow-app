import { Router } from "express";
import { z } from "zod";
import u from "@/utils";
import { validateFields } from "@/lib/middleware";
import { success } from "@/lib/responseFormat";

const router = Router();

export default router.post("/", validateFields({ directory: z.string().min(1).max(4096), path: z.string().max(4096), target: z.string().min(1).max(4096) }), async (req, res) => {
  const store = u.storage.getWorkspaceStore();
  const workspace = await store.resolveWorkspace(req, req.body.directory);
  await store.rename(workspace, req.body.path, req.body.target);
  res.json(success());
});
