import { createClient } from "@supabase/supabase-js";
import type { Request } from "express";
import { getSession } from "@/utils/gatewayAuth";
import type { WorkspaceEntry, WorkspaceStat, WorkspaceStore } from "@/utils/storage";

export interface SupabaseStorageConfig {
  url: string;
  serviceRoleKey: string;
  bucket: string;
}

interface ListedEntry {
  name: string;
  id: string | null;
  metadata: { size?: number } | null;
}

const pageSize = 1000;
const removeBatchSize = 100;
const keepFileName = ".keep";
const illegalSegment = /[<>:"|?*\\\x00-\x1f]/;
const reservedName = /^(con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\.|$)/i;

const contentTypes: Record<string, string> = {
  json: "application/json",
  txt: "text/plain; charset=utf-8",
  md: "text/markdown; charset=utf-8",
  csv: "text/csv; charset=utf-8",
  html: "text/html; charset=utf-8",
  css: "text/css; charset=utf-8",
  js: "text/javascript; charset=utf-8",
  png: "image/png",
  jpg: "image/jpeg",
  jpeg: "image/jpeg",
  gif: "image/gif",
  webp: "image/webp",
  svg: "image/svg+xml",
  mp4: "video/mp4",
  webm: "video/webm",
  mov: "video/quicktime",
  mp3: "audio/mpeg",
  wav: "audio/wav",
  ogg: "audio/ogg",
  m4a: "audio/mp4",
  woff2: "font/woff2",
  otf: "font/otf",
  ttf: "font/ttf",
};

function forbidden(): never {
  throw Object.assign(new Error("只能访问当前账号的工作区"), { status: 403 });
}

function invalidPath(): never {
  throw Object.assign(new Error("文件路径无效"), { status: 400 });
}

function throwStorageError(error: unknown, fallback: string): never {
  const statusCode = Number((error as { statusCode?: number | string } | null)?.statusCode);
  const message = error instanceof Error && error.message ? error.message : fallback;
  if (statusCode === 404) throw Object.assign(new Error("找不到这个文件或文件夹，可能已被移动、删除，或者位置选错了。"), { status: 404, code: "ENOENT" });
  if (statusCode === 400) throw Object.assign(new Error(message), { status: 400 });
  if (statusCode === 401 || statusCode === 403) throw Object.assign(new Error("没有权限访问对象存储"), { status: 403 });
  throw Object.assign(new Error(message), { status: 500 });
}

function normalizeWorkspaceIdentifier(directory: string, sub: string): string {
  if (!directory || directory.includes("\0") || directory.startsWith("/") || directory.includes("\\")) forbidden();
  const segments = directory.split("/").filter(segment => segment !== "");
  if (segments.length < 2 || segments[0] !== "saas" || segments[1] !== sub) forbidden();
  if (segments.some(segment => segment === "." || segment === ".." || illegalSegment.test(segment) || /[. ]$/.test(segment))) forbidden();
  return segments.join("/");
}

function normalizeRelativePath(path: string): string {
  if (path.includes("\0") || path.startsWith("/") || path.startsWith("\\") || /^[a-zA-Z]:/.test(path)) invalidPath();
  const segments = path.split("/").filter(segment => segment !== "" && segment !== ".");
  for (const segment of segments) {
    if (segment === ".." || illegalSegment.test(segment) || /[. ]$/.test(segment) || reservedName.test(segment)) invalidPath();
  }
  return segments.join("/");
}

function objectKey(workspace: string, relativePath: string): string {
  const normalized = normalizeRelativePath(relativePath);
  return normalized ? `${workspace}/${normalized}` : workspace;
}

function isDirectoryEntry(entry: ListedEntry): boolean {
  return entry.id === null || entry.metadata === null;
}

function isIgnoredPath(relativePath: string): boolean {
  return relativePath.split("/").some(part => ["assets", ".agent"].includes(part.toLowerCase()));
}

function contentTypeFor(relativePath: string): string {
  const match = /\.([a-zA-Z0-9]+)$/.exec(relativePath);
  return (match && contentTypes[match[1].toLowerCase()]) || "application/octet-stream";
}

export function createSupabaseStore(config: SupabaseStorageConfig): WorkspaceStore {
  const client = createClient(config.url, config.serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
  });
  const storage = client.storage.from(config.bucket);

  async function listPage(prefix: string): Promise<ListedEntry[]> {
    const entries: ListedEntry[] = [];
    for (let offset = 0; ; offset += pageSize) {
      const { data, error } = await storage.list(prefix, { limit: pageSize, offset });
      if (error) throwStorageError(error, "读取对象存储目录失败");
      entries.push(...(data ?? []));
      if (!data || data.length < pageSize) break;
    }
    return entries;
  }

  async function downloadBytes(key: string): Promise<Uint8Array> {
    const { data, error } = await storage.download(key);
    if (error || !data) throwStorageError(error, "读取对象存储文件失败");
    return new Uint8Array(await data.arrayBuffer());
  }

  async function removeKeys(keys: string[]): Promise<void> {
    for (let index = 0; index < keys.length; index += removeBatchSize) {
      const { error } = await storage.remove(keys.slice(index, index + removeBatchSize));
      if (error) throwStorageError(error, "删除对象存储文件失败");
    }
  }

  async function moveObject(from: string, to: string): Promise<void> {
    const { error } = await storage.move(from, to);
    if (error) throwStorageError(error, "移动对象存储文件失败");
  }

  async function listObjectKeys(prefix: string): Promise<string[]> {
    const entries = await listPage(prefix);
    const keys: string[] = [];
    for (const entry of entries) {
      const key = `${prefix}/${entry.name}`;
      if (isDirectoryEntry(entry)) keys.push(...await listObjectKeys(key));
      else keys.push(key);
    }
    return keys;
  }

  async function statKey(key: string): Promise<WorkspaceStat> {
    const slash = key.lastIndexOf("/");
    const parent = slash < 0 ? "" : key.slice(0, slash);
    const name = slash < 0 ? key : key.slice(slash + 1);
    const entry = (await listPage(parent)).find(item => item.name === name);
    if (entry) return isDirectoryEntry(entry) ? { type: "directory", size: 0 } : { type: "file", size: entry.metadata?.size ?? 0 };
    if ((await listPage(key)).length > 0) return { type: "directory", size: 0 };
    throw Object.assign(new Error("找不到这个文件或文件夹，可能已被移动、删除，或者位置选错了。"), { status: 404, code: "ENOENT" });
  }

  // ACT: 画布识别需要下载候选 JSON 全文；仅在删除包含画布的路径时启用，大量非画布 JSON 会增加读取量。
  async function isCanvasObject(key: string): Promise<boolean> {
    const bytes = await downloadBytes(key);
    const text = new TextDecoder("utf-8", { fatal: false }).decode(bytes);
    if (!/^\s*\{/.test(text)) return false;
    if (/^\s*\{\s*"toonflowCanvas"\s*:\s*true\s*[,}]/.test(text)) return true;
    try {
      return JSON.parse(text.trimStart())?.toonflowCanvas === true;
    } catch {
      return false;
    }
  }

  async function findCanvasKeys(prefix: string): Promise<string[]> {
    const keys = await listObjectKeys(prefix);
    const found: string[] = [];
    for (const key of keys) {
      const relativePath = key.slice(prefix.length).replace(/^\//, "");
      if (!/\.json$/i.test(key) || isIgnoredPath(relativePath)) continue;
      if (await isCanvasObject(key)) found.push(key);
    }
    return found;
  }

  async function remainingCanvasKeys(workspace: string, targetKey: string, targetType: "file" | "directory"): Promise<string[]> {
    const keys = await listObjectKeys(workspace);
    const found: string[] = [];
    for (const key of keys) {
      if (targetType === "file" ? key === targetKey : key === targetKey || key.startsWith(`${targetKey}/`)) continue;
      const relativePath = key.slice(workspace.length + 1);
      if (!/\.json$/i.test(key) || isIgnoredPath(relativePath)) continue;
      if (await isCanvasObject(key)) found.push(key);
    }
    return found;
  }

  return {
    mode: "supabase",

    async resolveWorkspace(req: Request, directory: string) {
      const sessionId = req.cookies?.gateway_session;
      const session = sessionId ? getSession(sessionId) : undefined;
      if (!session) forbidden();
      return normalizeWorkspaceIdentifier(directory, session.sub);
    },

    async list(workspace, path) {
      const relativePath = normalizeRelativePath(path);
      const key = relativePath ? `${workspace}/${relativePath}` : workspace;
      const entries = await listPage(key);
      if (entries.length === 0 && relativePath) {
        // 空结果可能是文件或路径不存在，补齐与本地 readdir 一致的错误语义。
        if ((await statKey(key)).type === "file") throw Object.assign(new Error("只能读取文件夹"), { status: 400 });
      }
      return entries
        .filter(entry => !(entry.name === keepFileName && !isDirectoryEntry(entry)))
        .map((entry): WorkspaceEntry => ({
          name: entry.name,
          path: relativePath ? `${relativePath}/${entry.name}` : entry.name,
          type: isDirectoryEntry(entry) ? "directory" : "file",
        }))
        .sort((a, b) => a.name.localeCompare(b.name, "zh-CN", { numeric: true }));
    },

    async read(workspace, path) {
      const relativePath = normalizeRelativePath(path);
      if (!relativePath) invalidPath();
      return downloadBytes(objectKey(workspace, relativePath));
    },

    async write(workspace, path, data) {
      const relativePath = normalizeRelativePath(path);
      if (!relativePath) invalidPath();
      const body = typeof data === "string" ? new TextEncoder().encode(data) : data;
      const { error } = await storage.upload(objectKey(workspace, relativePath), body, {
        upsert: true,
        contentType: contentTypeFor(relativePath),
      });
      if (error) throwStorageError(error, "写入对象存储文件失败");
    },

    async remove(workspace, path, recursive) {
      const relativePath = normalizeRelativePath(path);
      if (!relativePath) throw Object.assign(new Error("不能修改工作区根目录"), { status: 400 });
      const key = objectKey(workspace, relativePath);
      const info = await statKey(key);
      // 与本地 rmdir 一致：非递归删除目录只允许空目录（Supabase 用 .keep 占位）。
      if (info.type === "directory" && !recursive) {
        const keys = await listObjectKeys(key);
        const visible = keys.filter(child => child !== `${key}/${keepFileName}`);
        if (visible.length > 0) throw Object.assign(new Error("这个文件夹里还有内容，不能直接删除。请先清空或移走里面的文件。"), { status: 409, code: "ENOTEMPTY" });
        if (keys.length > 0) await removeKeys(keys);
        return;
      }
      if (!isIgnoredPath(relativePath)) {
        const affected = info.type === "file"
          ? (/\.json$/i.test(key) && await isCanvasObject(key) ? [key] : [])
          : await findCanvasKeys(key);
        if (affected.length > 0 && (await remainingCanvasKeys(workspace, key, info.type)).length === 0) {
          throw Object.assign(new Error("项目里需要保留至少一个画布。你可以先新建一个，再删除这个画布。"), { status: 409, code: "ELASTCANVAS" });
        }
      }
      if (info.type === "file") {
        await removeKeys([key]);
        return;
      }
      const keys = await listObjectKeys(key);
      if (keys.length > 0) await removeKeys(keys);
    },

    async rename(workspace, from, to) {
      const fromKey = objectKey(workspace, from);
      const toKey = objectKey(workspace, to);
      const prefix = workspace.split("/").slice(0, 2).join("/");
      if (!fromKey.startsWith(`${prefix}/`) || !toKey.startsWith(`${prefix}/`)) forbidden();
      if (fromKey === toKey) return;
      const info = await statKey(fromKey);
      const existing = await statKey(toKey).catch(error => {
        if ((error as { status?: number }).status === 404) return null;
        throw error;
      });
      if (existing) throw Object.assign(new Error("已存在同名文件或目录"), { status: 409, code: "EEXIST" });
      if (info.type === "file") {
        await moveObject(fromKey, toKey);
        return;
      }
      for (const key of await listObjectKeys(fromKey)) {
        await moveObject(key, toKey + key.slice(fromKey.length));
      }
    },

    async mkdir(workspace, path) {
      const relativePath = normalizeRelativePath(path);
      if (!relativePath) invalidPath();
      const { error } = await storage.upload(`${objectKey(workspace, relativePath)}/${keepFileName}`, new Uint8Array(0), {
        upsert: true,
        contentType: "application/octet-stream",
      });
      if (error) throwStorageError(error, "创建对象存储目录失败");
    },

    async stat(workspace, path) {
      const relativePath = normalizeRelativePath(path);
      if (!relativePath) return { type: "directory", size: 0 };
      return statKey(objectKey(workspace, relativePath));
    },

    async exists(workspace, path) {
      const relativePath = normalizeRelativePath(path);
      if (!relativePath) return true;
      try {
        await statKey(objectKey(workspace, relativePath));
        return true;
      } catch (error) {
        if ((error as { status?: number }).status === 404) return false;
        throw error;
      }
    },
  };
}
