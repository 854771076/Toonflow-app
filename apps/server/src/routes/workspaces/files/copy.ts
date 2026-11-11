import { Router } from "express";
import { z } from "zod";
import u from "@/utils";
import { validateFields } from "@/lib/middleware";
import { error, success } from "@/lib/responseFormat";

const router = Router();

function isWorkspaceRoot(path: string) {
  return !path.split(/[\\/]/).some(part => part && part !== ".");
}

export default router.post("/", validateFields({ directory: z.string().min(1).max(4096), path: z.string().min(1).max(4096), target: z.string().min(1).max(4096) }), async (req, res) => {
  if (isWorkspaceRoot(req.body.path) || isWorkspaceRoot(req.body.target)) {
    throw Object.assign(new Error("不能修改工作区根目录"), { status: 400 });
  }
  const store = u.storage.getWorkspaceStore();
  const workspace = await store.resolveWorkspace(req, req.body.directory);

  async function copyEntry(from: string, to: string) {
    const info = await store.stat(workspace, from);
    if (info.type === "directory" && (to === from || to.startsWith(`${from}/`))) {
      throw Object.assign(new Error("不能把文件夹复制到自身或子目录"), { status: 400 });
    }
    if (await store.exists(workspace, to)) throw Object.assign(new Error("已存在同名文件或目录"), { status: 409, code: "EEXIST" });
    if (info.type === "file") {
      await store.write(workspace, to, await store.read(workspace, from));
      return;
    }
    await store.mkdir(workspace, to);
    try {
      for (const child of await store.list(workspace, from)) await copyEntry(child.path, `${to}/${child.name}`);
    } catch (cause) {
      // ACT: 与本地复制一致，失败保留已复制内容，不递归回滚删除目标目录。
      throw Object.assign(new Error(`复制未完成，已复制的内容保留在 ${to}。`, { cause }), { code: "ECOPYINCOMPLETE" });
    }
  }

  try { await copyEntry(req.body.path, req.body.target); }
  catch (cause) {
    if (!(cause instanceof Error) || (cause as NodeJS.ErrnoException).code !== "ECOPYINCOMPLETE") throw cause;
    return res.status(500).json(error(cause.message, { code: "ECOPYINCOMPLETE", partial: true, target: req.body.target }, 500));
  }
  res.json(success());
});
