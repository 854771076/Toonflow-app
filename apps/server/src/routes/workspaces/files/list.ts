import { Router } from "express";
import { z } from "zod";
import u from "@/utils";
import { validateFields } from "@/lib/middleware";
import { success } from "@/lib/responseFormat";

const router = Router();

export default router.get("/", validateFields({ directory: z.string().min(1).max(4096), path: z.string().max(4096).optional() }, "query"), async (req, res) => {
  const store = u.storage.getWorkspaceStore();
  const directory = await store.resolveWorkspace(req, req.query.directory as string);
  const entries = await store.list(directory, (req.query.path as string | undefined) ?? "");
  res.set("Cache-Control", "no-store").json(success({
    directory,
    empty: entries.length === 0,
    entries,
  }));
});
