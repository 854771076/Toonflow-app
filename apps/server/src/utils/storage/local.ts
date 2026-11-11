import { lstat, mkdir, readFile, readdir, writeAtomic } from "@toonflow/file";
import { join, relative, sep } from "node:path";
import * as workspace from "@/utils/workspace";
import * as workspaceFile from "@/utils/workspace/files";
import type { WorkspaceEntry, WorkspaceStore } from "@/utils/storage";

async function resolveEntry(root: string, path: string) {
  return workspaceFile.resolveWorkspacePath(root, path);
}

function isMissing(error: unknown) {
  const code = (error as NodeJS.ErrnoException).code;
  return code === "ENOENT" || code === "ENOTDIR";
}

export function createLocalStore(): WorkspaceStore {
  return {
    mode: "local",

    async resolveWorkspace(req, directory) {
      return workspace.resolveWorkspace(req, directory);
    },

    async list(root, path) {
      const target = await resolveEntry(root, path);
      const entries = await readdir(target.path, { withFileTypes: true });
      return entries
        .filter(entry => entry.isFile() || entry.isDirectory())
        .map((entry): WorkspaceEntry => ({
          name: entry.name,
          path: relative(target.directory, join(target.path, entry.name)).split(sep).join("/"),
          type: entry.isDirectory() ? "directory" : "file",
        }))
        .sort((a, b) => a.name.localeCompare(b.name, "zh-CN", { numeric: true }));
    },

    async read(root, path) {
      const target = await resolveEntry(root, path);
      const info = await lstat(target.path);
      if (!info.isFile()) throw Object.assign(new Error("只能读取文件"), { status: 400 });
      return readFile(target.path);
    },

    async write(root, path, data) {
      const target = await resolveEntry(root, path);
      await writeAtomic(target.path, data);
    },

    async remove(root, path, recursive) {
      const target = await resolveEntry(root, path);
      await workspaceFile.removeWorkspaceFile(root, target.path, recursive);
    },

    async rename(root, from, to) {
      const source = await resolveEntry(root, from);
      const target = await resolveEntry(root, to);
      // 同路径（Windows 仅大小写不同）交给 renameWorkspaceFile 原逻辑处理，不按目标已存在拒绝。
      if (source.path !== target.path) {
        const existing = await lstat(target.path).catch(error => {
          if (isMissing(error)) return null;
          throw error;
        });
        if (existing) throw Object.assign(new Error("已存在同名文件或目录"), { status: 409, code: "EEXIST" });
      }
      await workspaceFile.renameWorkspaceFile(source.path, target.path);
    },

    async mkdir(root, path) {
      const target = await resolveEntry(root, path);
      await mkdir(target.path);
    },

    async stat(root, path) {
      const target = await resolveEntry(root, path);
      const info = await lstat(target.path);
      if (info.isDirectory()) return { type: "directory", size: 0 };
      return { type: "file", size: info.size };
    },

    async exists(root, path) {
      const target = await workspaceFile.resolveWorkspacePath(root, path, true);
      const info = await lstat(target.path).catch(error => {
        if (isMissing(error)) return null;
        throw error;
      });
      return info !== null;
    },
  };
}
