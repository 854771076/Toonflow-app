import type { Request } from "express";
import { lstat, mkdir, realpath, stat } from "@toonflow/file";
import { dirname, isAbsolute, relative, resolve, sep } from "node:path";
import conf from "@/utils/conf";
import { getMobileLinkConfig, isMobileLinkRequest } from "@/utils/mobileLink";
import { getRuntimePlatform } from "@/lib/platform";
import * as gatewayAuth from "@/utils/gatewayAuth";
import { getStorageMode } from "@/utils/storage/config";

export function isLocalHostRequest(req: Request) {
  if (isMobileLinkRequest(req)) return false;
  const localAddress = ["127.0.0.1", "::1", "::ffff:127.0.0.1"].includes(req.socket.remoteAddress ?? "") && req.get("x-toonflow-local-client") !== "0";
  const localHost = ["localhost", "127.0.0.1", "[::1]"].includes(req.hostname);
  return localAddress && localHost;
}

export async function getWorkspaceRoot(req: Request) {
  const sessionId = req.cookies?.gateway_session;
  const session = sessionId ? gatewayAuth.getSession(sessionId) : undefined;

  // 对象存储模式不落本地磁盘，工作区用 saas/<sub>/projects 逻辑前缀表示。
  if (getStorageMode() === "supabase") {
    if (!session) throw Object.assign(new Error("请先登录"), { status: 401 });
    return `saas/${session.sub}/projects`;
  }

  let root = await realpath(dirname(conf.path));

  let path: string;
  if (session) {
    path = resolve(root, "saas", session.sub, "projects");
  } else {
    path = resolve(root, "workspaces");
  }

  try { await mkdir(path, { recursive: true, mode: 0o700 }); }
  catch (error) { if ((error as NodeJS.ErrnoException).code !== "EEXIST") throw error; }
  const info = await lstat(path);
  if (!info.isDirectory() || info.isSymbolicLink()) throw Object.assign(new Error("工作区目录必须是普通目录"), { status: 403 });
  const actual = await realpath(path);
  const offset = relative(root, actual);
  if (offset === ".." || offset.startsWith(`..${sep}`) || isAbsolute(offset)) {
    throw Object.assign(new Error("只能访问当前账号的工作区"), { status: 403 });
  }
  return actual;
}

export function isLocalWorkspaceRequest(req: Request) {
  const origin = req.get("origin");
  const localOrigin = `${req.protocol}://${req.get("host")}`;
  const sameOrigin = origin === undefined ? req.get("referer")?.startsWith(`${localOrigin}/`) : origin === localOrigin;
  return isLocalHostRequest(req) && sameOrigin && req.get("x-toonflow-workspace") === "1";
}

export async function resolveWorkspace(req: Request, path: string) {
  if (!isAbsolute(path)) throw Object.assign(new Error("工作目录必须是绝对路径"), { status: 400 });
  if (path.includes("\0")) throw Object.assign(new Error("路径包含非法字符"), { status: 400 });

  const sessionId = req.cookies?.gateway_session;
  const session = sessionId ? gatewayAuth.getSession(sessionId) : undefined;

  if (session) {
    // SaaS 模式：lstat 原始路径排除 symlink，再 realpath 归一化，最后确认在用户 projects 下
    const precheck = await lstat(path).catch((err: NodeJS.ErrnoException) => {
      if (err.code === "ENOENT" || err.code === "ENOTDIR") throw Object.assign(new Error("工作目录不存在，请重新选择文件夹"), { status: 404 });
      throw err;
    });
    if (precheck.isSymbolicLink()) throw Object.assign(new Error("工作目录不能是符号链接"), { status: 403 });

    const directory = await realpath(path).catch((err: NodeJS.ErrnoException) => {
      if (err.code === "ENOENT" || err.code === "ENOTDIR") throw Object.assign(new Error("工作目录不存在，请重新选择文件夹"), { status: 404 });
      throw err;
    });
    if (!(await stat(directory)).isDirectory()) throw Object.assign(new Error("工作目录不是文件夹，请重新选择"), { status: 404 });

    const root = await getWorkspaceRoot(req);
    const offset = relative(root, directory);
    if (offset === ".." || offset.startsWith(`..${sep}`) || isAbsolute(offset)) {
      throw Object.assign(new Error("只能访问当前账号的工作区"), { status: 403 });
    }
    return directory;
  }

  // 桌面端 / 匿名服务器模式，保持原逻辑不变
  const directory = await realpath(path).catch((err: NodeJS.ErrnoException) => {
    if (err.code === "ENOENT" || err.code === "ENOTDIR") throw Object.assign(new Error("工作目录不存在，请重新选择文件夹"), { status: 404 });
    throw err;
  });
  if (!(await stat(directory)).isDirectory()) throw Object.assign(new Error("工作目录不是文件夹，请重新选择"), { status: 404 });
  if (getRuntimePlatform().local && isLocalWorkspaceRequest(req)) return directory;

  if (isMobileLinkRequest(req)) {
    for (const root of getMobileLinkConfig().directories) {
      const offset = relative(root, directory);
      if (offset !== ".." && !offset.startsWith(`..${sep}`) && !isAbsolute(offset)) return directory;
    }
  }

  const root = await realpath(resolve(dirname(conf.path), "workspaces")).catch((err: NodeJS.ErrnoException) => {
    if (err.code === "ENOENT") return null;
    throw err;
  });
  if (root) {
    const offset = relative(root, directory);
    if (offset !== ".." && !offset.startsWith(`..${sep}`) && !isAbsolute(offset)) return directory;
  }
  throw Object.assign(new Error("服务器部署只能使用服务器工作区"), { status: 403 });
}
