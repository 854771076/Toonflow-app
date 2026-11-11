import { Router } from "express";
import { realpath } from "@toonflow/file";
import { dirname, relative, resolve, sep } from "node:path";
import { z } from "zod";
import u from "@/utils";
import { validateFields } from "@/lib/middleware";
import { error, success } from "@/lib/responseFormat";

const router = Router();

export default router.get("/", validateFields({ path: z.string().max(4096).optional() }, "query"), async (req, res) => {
  const store = u.storage.getWorkspaceStore();
  if (store.mode === "supabase") {
    const workspace = await store.resolveWorkspace(req, await u.workspace.getWorkspaceRoot(req));
    const path = ((req.query.path as string | undefined) ?? "").replace(/\\/g, "/").replace(/^\/+|\/+$/g, "");
    if (path) {
      const info = await store.stat(workspace, path).catch(() => undefined);
      if (!info) return res.status(404).json(error("目录不存在", null, 404));
      if (info.type !== "directory") return res.status(400).json(error("只能选择服务器工作区内的目录", null, 400));
    }
    const entries = await store.list(workspace, path);
    return res.set("Cache-Control", "no-store").json(success({
      path,
      absolutePath: path ? `${workspace}/${path}` : workspace,
      parent: path ? path.split("/").slice(0, -1).join("/") : null,
      directories: entries.filter(entry => entry.type === "directory").map(entry => ({ name: entry.name, path: entry.path }))
        .sort((a, b) => a.name.localeCompare(b.name, "zh-CN", { numeric: true })),
    }));
  }
  const root = await u.workspace.getWorkspaceRoot(req);
  const workspace = await store.resolveWorkspace(req, root);
  const target = resolve(root, (req.query.path as string | undefined) ?? "");
  if (!u.workspaceFile.isWithin(root, target)) return res.status(403).json(error("只能选择服务器工作区内的目录", null, 403));
  try {
    const directory = await realpath(target);
    if (!u.workspaceFile.isWithin(root, directory)) return res.status(403).json(error("只能选择服务器工作区内的目录", null, 403));
    const path = relative(root, directory).split(sep).join("/");
    const entries = await store.list(workspace, path);
    res.set("Cache-Control", "no-store").json(success({
      path,
      absolutePath: directory,
      parent: path ? relative(root, dirname(directory)).split(sep).join("/") : null,
      directories: entries.filter(entry => entry.type === "directory").map(entry => ({ name: entry.name, path: entry.path }))
        .sort((a, b) => a.name.localeCompare(b.name, "zh-CN", { numeric: true })),
    }));
  } catch (err) {
    const code = (err as NodeJS.ErrnoException).code;
    if (code === "ENOENT" || code === "ENOTDIR") return res.status(404).json(error("目录不存在", null, 404));
    if (code === "EACCES" || code === "EPERM") return res.status(403).json(error("没有权限访问此目录", null, 403));
    throw err;
  }
});
