import { createHash } from "node:crypto";
import { dirname, join, relative } from "node:path";
import { lstat, mkdir, readFile, realpath, writeAtomic } from "@toonflow/file";
import type { ProviderTaskData } from "@toonflow/providers";
import type { GeneratedMedia, MediaGenerationRequest } from "@toonflow/tools-scaffold/runtime";
import { audioGenerationSchema, imageGenerationSchema, videoGenerationSchema } from "@/utils/media/schemas";
import { z } from "zod";
import { error, errorFromCause, success } from "@/lib/responseFormat";
import conf from "@/utils/conf";
import { generateMedia, isMediaNotSubmitted, type MediaGenerationCheckpoint } from "@/utils/media/generation";
import { lockWorkspaceFiles, resolveWorkspacePath } from "@/utils/workspace/files";
import { getWorkspaceStore } from "@/utils/storage";
import { readPriceReference } from "@/utils/media/priceReference";

type TaskOwnerIdentity = { role?: string; id?: string } | null | undefined;

const maxRecordSize = 16 * 1024 * 1024;
const maxBlobSize = 140 * 1024 * 1024;
const mediaTypeSchema = z.enum(["image", "video", "audio"]);
const relativePathSchema = z.string().min(1).max(4096).refine(value => !/^[\\/]|[:\u0000-\u001f]/.test(value)
  && value.split(/[\\/]/).every(part => part && part !== "." && part !== ".."));
const hashSchema = z.string().regex(/^[a-f0-9]{64}$/);
const mediaSchema = z.strictObject({ path: relativePathSchema, mimeType: z.string().min(1).max(256), mediaType: mediaTypeSchema });
const checkpointSchema = z.strictObject({
  providerData: z.record(z.string(), z.json()).optional(),
  assets: z.array(z.strictObject({
    type: z.literal("url"), mediaType: mediaTypeSchema, url: z.string().regex(/^https?:\/\//i),
    mimeType: z.string().optional(), name: z.string().optional(),
  })).optional(),
  assetCount: z.number().int().positive().optional(),
  files: z.array(mediaSchema.extend({ index: z.number().int().nonnegative(), hash: hashSchema })).optional(),
});
const blobSchema = z.strictObject({
  path: z.array(z.union([z.string(), z.number().int().nonnegative()])).min(1).max(32),
  hash: hashSchema, size: z.number().int().positive().max(maxBlobSize),
});
const requestSchemas = { image: imageGenerationSchema, video: videoGenerationSchema, audio: audioGenerationSchema };
const recordSchema = z.strictObject({
  version: z.literal(1), taskId: z.uuid(), cwd: z.string().min(1).max(4096),
  mediaType: mediaTypeSchema.optional(),
  request: z.union([imageGenerationSchema, videoGenerationSchema, audioGenerationSchema]).optional(),
  nodeId: z.string().min(1).max(512).optional(), canvasPath: relativePathSchema.optional(),
  ownerUserId: z.uuid().optional(), modelRouteCipher: z.string().min(1).max(8 * 1024 * 1024).optional(),
  chargeId: z.string().min(1).max(128).optional(),
  chargeStatus: z.enum(["settled", "released", "pendingReview"]).optional(),
  state: z.enum(["running", "interrupted", "succeeded", "failed", "cancelled"]),
  createdAt: z.number().finite().nonnegative(), updatedAt: z.number().finite().nonnegative(),
  checkpoint: checkpointSchema,
  blobs: z.array(blobSchema).optional(),
  result: z.strictObject({ code: z.number().int(), data: z.array(mediaSchema).nullable(), message: z.string() }).optional(),
}).superRefine((record, context) => {
  const issue = (message: string) => context.addIssue({ code: "custom", message });
  if (!record.request || !record.mediaType) {
    if (record.state !== "cancelled" || record.request || record.mediaType) issue("任务缺少生成请求");
  } else if (!requestSchemas[record.mediaType].safeParse(record.request).success) issue("任务生成请求无效");
  if (record.state === "running" ? record.result !== undefined : record.result === undefined) issue("任务状态与结果不一致");
  if (record.state === "succeeded" && (record.result?.code !== 200 || !record.result.data?.length)) issue("任务成功结果无效");
  if (record.result && record.state !== "succeeded" && (record.result.code === 200 || record.result.data !== null)) issue("任务错误结果无效");
  const { assetCount, assets, files } = record.checkpoint;
  if (assets && (assetCount !== assets.length || assets.some(asset => asset.mediaType !== record.mediaType))) issue("任务媒体结果无效");
  if (files?.length && (assetCount === undefined || new Set(files.map(file => file.index)).size !== files.length
    || files.some(file => file.index >= assetCount || file.mediaType !== record.mediaType))) issue("任务文件索引无效");
  if (record.result?.data?.some(file => file.mediaType !== record.mediaType)) issue("任务结果类型无效");
  if (record.blobs?.length && (!record.checkpoint.providerData || new Set(record.blobs.map(blob => JSON.stringify(blob.path))).size !== record.blobs.length)) issue("任务媒体引用无效");
});

type TaskRecord = Omit<z.infer<typeof recordSchema>, "blobs" | "checkpoint"> & { checkpoint: MediaGenerationCheckpoint };
type BlobReference = z.infer<typeof blobSchema>;
type MediaTask = {
  key: string;
  record: TaskRecord;
  blobs: BlobReference[];
  prepared?: { source: ProviderTaskData; data: ProviderTaskData; blobs: BlobReference[] };
  active: boolean;
  controller?: AbortController;
  settledAt?: number;
  persistenceError?: unknown;
  completion?: Promise<void>;
  chargeFinalized?: boolean;
};
type TaskOwner = { nodeId?: string; canvasPath?: string };

// ACT: 单进程最多 1000 个执行中任务；磁盘记录保留，结束后只释放五分钟未用的内存缓存。
const tasks = new Map<string, MediaTask>();
const operations = new Map<string, Promise<void>>();
let activeCount = 0;

function invalid(message: string, status = 400): never { throw Object.assign(new Error(message), { status }); }
function requireOwner(_owner?: TaskOwnerIdentity) {
  // ACT: 非多租户模式下不需要登录校验。
}
function assertOwner(task: MediaTask, owner?: TaskOwnerIdentity) {
  // ACT: 非多租户模式下无 owner 概念，跳过权限校验。
  void task; void owner;
}
function identity(value: string) { return process.platform === "win32" ? value.toLowerCase() : value; }
async function normalizeWorkspace(cwd: string) {
  return getWorkspaceStore().mode === "local" ? await realpath(cwd) : cwd;
}
function taskPath(cwd: string, taskId: string) {
  z.uuid().parse(taskId);
  return join(dirname(conf.path), "mediaTasks", `workspace${createHash("sha256").update(identity(cwd)).digest("hex")}`, `task${taskId.replaceAll("-", "").toLowerCase()}.json`);
}
function serialize(value: unknown) {
  return JSON.stringify(value, (_key, item) => item && typeof item === "object" && !Array.isArray(item)
    ? Object.fromEntries(Object.entries(item).sort(([left], [right]) => left.localeCompare(right))) : item);
}
async function locked<T>(key: string, action: () => Promise<T>): Promise<T> {
  const next = (operations.get(key) ?? Promise.resolve()).then(action);
  // 队列只释放前一操作的占位；其错误仍由对应调用方接收。
  const tail = next.then(() => {}, () => {});
  operations.set(key, tail);
  try { return await next; }
  finally { if (operations.get(key) === tail) operations.delete(key); }
}
async function privateDirectory(path: string, create: boolean) {
  for (const folder of [dirname(path), path]) {
    let info = await lstat(folder).catch((cause: NodeJS.ErrnoException) => { if (cause.code === "ENOENT") return null; throw cause; });
    if (!info && create) {
      await mkdir(folder, { mode: 0o700 }).catch((cause: NodeJS.ErrnoException) => { if (cause.code !== "EEXIST") throw cause; });
      info = await lstat(folder);
    }
    if (!info) return false;
    if (!info.isDirectory() || info.isSymbolicLink()) invalid("任务数据目录不能是文件或符号链接", 403);
  }
  return true;
}
async function readPrivateFile(path: string, maxSize: number) {
  const info = await lstat(path);
  if (!info.isFile() || info.isSymbolicLink() || info.size > maxSize) invalid("任务记录或媒体文件无效");
  const bytes = await readFile(path);
  if (bytes.length > maxSize) invalid("任务记录或媒体文件过大");
  return bytes;
}

async function prepareBlobs(task: MediaTask) {
  const data = task.record.checkpoint.providerData;
  if (!data) { task.prepared = undefined; task.blobs = []; return { data, blobs: [] as BlobReference[] }; }
  if (task.blobs.length) return { data, blobs: task.blobs };
  if (task.prepared?.source === data) return task.prepared;
  const blobs: BlobReference[] = [];
  async function copy(value: ProviderTaskData[string], path: BlobReference["path"]): Promise<ProviderTaskData[string]> {
    if (typeof value === "string" && value.length > 4096 && /^data:(?:image|audio|video)\/[^,]*;base64,/i.test(value)) {
      const size = Buffer.byteLength(value, "utf8");
      if (size > maxBlobSize) invalid("任务参考媒体超过大小限制");
      const hash = createHash("sha256").update(value).digest("hex");
      const file = join(dirname(task.key), `media${hash}.bin`);
      const known = task.prepared?.blobs.some(blob => blob.hash === hash && blob.size === size);
      const info = known ? await lstat(file).catch((cause: NodeJS.ErrnoException) => { if (cause.code === "ENOENT") return null; throw cause; }) : undefined;
      // 同一任务推进阶段时复用已写入的素材，避免每次保存凭据都重写大文件；恢复时仍验证完整哈希。
      if (!info?.isFile() || info.isSymbolicLink() || info.size !== size) {
        try { await writeAtomic(file, value, { exclusive: true, mode: 0o600 }); }
        catch (cause) {
          if ((cause as NodeJS.ErrnoException).code !== "EEXIST") throw cause;
          const bytes = await readPrivateFile(file, maxBlobSize);
          if (bytes.length !== size || createHash("sha256").update(bytes).digest("hex") !== hash) invalid("任务参考媒体校验失败");
        }
      }
      blobs.push({ path, hash, size });
      return "";
    }
    if (Array.isArray(value)) {
      const result: ProviderTaskData[string][] = [];
      for (const [index, child] of value.entries()) result.push(await copy(child, [...path, index]));
      return result;
    }
    if (value && typeof value === "object") {
      const entries: [string, ProviderTaskData[string]][] = [];
      for (const [key, child] of Object.entries(value)) entries.push([key, await copy(child, [...path, key])]);
      return Object.fromEntries(entries);
    }
    return value;
  }
  task.prepared = { source: data, data: await copy(data, []) as ProviderTaskData, blobs };
  return task.prepared;
}

async function restoreBlobs(task: MediaTask) {
  if (!task.blobs.length) return;
  const source = task.record.checkpoint.providerData;
  if (!source) invalid("任务缺少媒体恢复数据");
  const data = structuredClone(source);
  for (const blob of task.blobs) {
    let parent: ProviderTaskData[string] = data;
    for (const key of blob.path.slice(0, -1)) {
      if (!parent || typeof parent !== "object" || !Object.hasOwn(parent, key)) invalid("任务媒体引用路径无效");
      parent = (parent as Record<string | number, ProviderTaskData[string]>)[key];
    }
    const key = blob.path.at(-1)!;
    if (!parent || typeof parent !== "object" || !Object.hasOwn(parent, key)
      || (parent as Record<string | number, unknown>)[key] !== "") invalid("任务媒体引用位置无效");
    const bytes = await readPrivateFile(join(dirname(task.key), `media${blob.hash}.bin`), maxBlobSize);
    if (bytes.length !== blob.size || createHash("sha256").update(bytes).digest("hex") !== blob.hash) invalid("任务参考媒体校验失败");
    const value = bytes.toString("utf8");
    if (!/^data:(?:image|audio|video)\/[^,]*;base64,/i.test(value)) invalid("任务参考媒体内容无效");
    Object.defineProperty(parent, key, { value, enumerable: true, configurable: true, writable: true });
  }
  task.prepared = { source: data, data: source, blobs: task.blobs };
  task.record.checkpoint.providerData = data;
  task.blobs = [];
}

async function persist(task: MediaTask, exclusive = false) {
  try {
    await privateDirectory(dirname(task.key), true);
    const prepared = await prepareBlobs(task);
    task.record.updatedAt = Date.now();
    const stored = recordSchema.parse({ ...task.record, checkpoint: { ...task.record.checkpoint, providerData: prepared.data }, blobs: prepared.blobs });
    const content = JSON.stringify(stored);
    if (Buffer.byteLength(content, "utf8") > maxRecordSize) invalid("任务元数据不能超过 16 MB");
    await writeAtomic(task.key, content, { exclusive, mode: 0o600 });
    task.persistenceError = undefined;
    if (task.record.state === "cancelled") task.controller?.abort(new Error("生成已取消"));
  } catch (cause) { task.persistenceError = cause; throw cause; }
}

async function load(cwd: string, taskId: string, key: string, owner?: TaskOwnerIdentity) {
  const cached = tasks.get(key);
  if (cached) { assertOwner(cached, owner); cached.settledAt = cached.active ? undefined : Date.now(); return cached; }
  if (!await privateDirectory(dirname(key), false)) return undefined;
  let bytes: Buffer;
  try { bytes = await readPrivateFile(key, maxRecordSize); }
  catch (cause) { if ((cause as NodeJS.ErrnoException).code === "ENOENT") return undefined; throw cause; }
  const stored = recordSchema.parse(JSON.parse(bytes.toString("utf8")));
  const { blobs, ...record } = stored;
  const task: MediaTask = { key, record, blobs: blobs ?? [], active: false, settledAt: Date.now() };
  assertOwner(task, owner);
  if (identity(stored.cwd) !== identity(cwd) || stored.taskId.toLowerCase() !== taskId.toLowerCase()) invalid("任务不属于当前工作区", 403);
  if (stored.canvasPath) {
    if (getWorkspaceStore().mode === "local") await resolveWorkspacePath(cwd, stored.canvasPath, true);
    else await getWorkspaceStore().exists(cwd, stored.canvasPath);
  }
  tasks.set(key, task);
  return task;
}

async function resumable(task: MediaTask) {
  const { checkpoint, state } = task.record;
  if (state !== "running" && state !== "interrupted") return false;
  if (checkpoint.providerData || checkpoint.assets?.length) return true;
  if (!checkpoint.assetCount || checkpoint.files?.length !== checkpoint.assetCount) return false;
  const store = getWorkspaceStore();
  for (const file of checkpoint.files) {
    if (store.mode === "local") {
      const { path } = await resolveWorkspacePath(task.record.cwd, file.path, true);
      const info = await lstat(path).catch((cause: NodeJS.ErrnoException) => { if (cause.code === "ENOENT") return null; throw cause; });
      if (!info?.isFile() || info.isSymbolicLink()) return false;
    } else {
      const info = await store.stat(task.record.cwd, file.path).catch((cause: { status?: number }) => {
        if (cause.status === 404) return null;
        throw cause;
      });
      if (!info || info.type !== "file") return false;
    }
  }
  return true;
}

function publicData(task: MediaTask) {
  const data = task.record.checkpoint.providerData;
  if (!data || task.blobs.length || task.prepared?.blobs.length) return undefined;
  const pending: unknown[] = [data];
  while (pending.length) {
    const value = pending.pop();
    if (typeof value === "string") {
      if (/^data:/i.test(value)) return undefined;
      if (/^https?:\/\//i.test(value)) {
        try { const url = new URL(value); if (url.search || url.username || url.password) return undefined; }
        catch { return undefined; }
      }
    } else if (value && typeof value === "object") for (const child of Object.values(value)) pending.push(child);
  }
  return data;
}

async function snapshot(task: MediaTask, owner?: TaskOwnerIdentity) {
  const { taskId, state, nodeId, canvasPath, result } = task.record;
  void owner;
  return { taskId, state, resumable: await resumable(task), nodeId, canvasPath,
    providerData: publicData(task), ...(result ? { result } : {}) };
}

async function finalizeCharge(task: MediaTask, _outcome: unknown) {
  // ACT: 非多租户模式下无扣费系统，空操作。
  void task;
}

async function settleCharge(task: MediaTask, files: GeneratedMedia[], signal = task.controller?.signal) {
  // ACT: 非多租户模式下无扣费系统，chargeId/ownerUserId 不存在，始终在守卫处 return。
  void files; void signal;
  const { record } = task;
  if (!record.chargeId || !record.ownerUserId || task.chargeFinalized) return;
  // 以下代码在非多租户模式下不可达。
  if (record.chargeStatus === "settled" || record.chargeStatus === "released") { task.chargeFinalized = true; return; }
  if (!record.modelRouteCipher || !record.request || !record.mediaType) invalid("媒体任务扣费记录无效", 409);
  if (!files.length) invalid("媒体任务扣费记录无效", 409);
}

async function releaseCharge(task: MediaTask, notSubmitted = false) {
  const { record } = task;
  if (!record.ownerUserId || task.chargeFinalized || (!record.chargeId && !record.modelRouteCipher)) return;
  if (record.chargeStatus === "settled" || record.chargeStatus === "released") { task.chargeFinalized = true; return; }
  if (!record.chargeId) {
    // ACT: 非多租户模式下无扣费系统，chargeId 不会缺失。
    return;
  }
  if (record.checkpoint.files?.length) {
    // 输出记录写在公开文件之前；无法确认交付时保留预占，不能把取消作为拿到部分结果后的全额退款。
    record.chargeStatus = "pendingReview";
    try {
      await settleCharge(task, record.checkpoint.files.map(({ path, mimeType, mediaType }) => ({ path, mimeType, mediaType })), AbortSignal.timeout(15000));
    } catch {
      await persist(task);
      return;
    }
    await persist(task);
    return;
  }
  await finalizeCharge(task, notSubmitted ? { kind: "notSubmitted" }
    : { kind: record.state === "cancelled" ? "cancelled" : "failed", delivered: false });
}

async function reconcileCharge(task: MediaTask) {
  const previous = task.record.chargeStatus;
  if (task.record.state === "succeeded") await settleCharge(task, task.record.result?.data ?? []);
  else if (["failed", "cancelled"].includes(task.record.state)) await releaseCharge(task);
  if (task.record.chargeStatus !== previous) await persist(task);
}

async function prepareCharge(task: MediaTask, recoverExisting = false) {
  const { record } = task;
  if (!record.ownerUserId || record.chargeId) return false;
  // ACT: 非多租户模式下无扣费系统，不创建 chargeId。
  void recoverExisting; void record; void task;
  return false;
}

async function execute(task: MediaTask, resume: boolean) {
  const { record } = task;
  try {
    const files = await generateMedia(record.cwd, record.mediaType!, record.request!, task.controller!.signal, {
      taskId: record.taskId, resume, checkpoint: record.checkpoint, modelRouteCipher: record.modelRouteCipher,
      save: patch => locked(task.key, async () => {
        if (record.state !== "running") throw new Error("生成已停止");
        Object.assign(record.checkpoint, patch);
        await persist(task);
      }),
    });
    await locked(task.key, async () => {
      if (record.state !== "running") return;
      await settleCharge(task, files);
      record.state = "succeeded";
      record.result = success(files);
      await persist(task);
    });
  } catch (cause) {
    try {
      await locked(task.key, async () => {
        if (record.state !== "running") return;
        const notSubmitted = isMediaNotSubmitted(cause);
        record.state = notSubmitted || (cause as { code?: string } | null)?.code === "MEDIA_TASK_FAILED" ? "failed" : "interrupted";
        const result = errorFromCause(cause);
        record.result = { ...result, code: result.code === 200 ? 500 : result.code, data: null };
        await persist(task);
        if (record.state === "failed") await releaseCharge(task, notSubmitted);
      });
    } catch (failure) { task.persistenceError = failure; console.error("保存媒体任务失败", failure); }
  } finally {
    await locked(task.key, async () => {
      task.active = false;
      task.controller = undefined;
      task.settledAt = Date.now();
      activeCount--;
      if (task.prepared && task.prepared.source === record.checkpoint.providerData && task.prepared.blobs.length) {
        record.checkpoint.providerData = task.prepared.data;
        task.blobs = task.prepared.blobs;
        task.prepared = undefined;
      }
    });
  }
}

async function launch(task: MediaTask, resume: boolean, exclusive = false) {
  if (task.active) return;
  if (task.record.ownerUserId && (!task.record.modelRouteCipher || !task.record.chargeId)) invalid("媒体任务扣费记录无效", 409);
  // ACT: 非多租户模式下 ownerUserId 不存在，跳过扣费状态检查。
  if (activeCount >= 1000) {
    invalid("生成任务过多，请稍后重试", 429);
  }
  task.active = true;
  activeCount++;
  const previousState = task.record.state;
  const previousResult = task.record.result;
  try {
    await restoreBlobs(task);
    task.record.state = "running";
    task.record.result = undefined;
    task.controller = new AbortController();
    await persist(task, exclusive);
  } catch (cause) {
    task.record.state = previousState;
    task.record.result = previousResult;
    task.controller = undefined;
    task.active = false;
    activeCount--;
    throw cause;
  }
  task.completion = execute(task, resume);
}

export async function start(cwd: string, taskId: string, mediaType: "image" | "video" | "audio", request: MediaGenerationRequest,
  attachment: TaskOwner = {}, owner?: TaskOwnerIdentity) {
  requireOwner(owner);
  cwd = await normalizeWorkspace(cwd);
  const key = taskPath(cwd, taskId);
  const parsed = requestSchemas[mediaType].parse(request);
  if (attachment.nodeId !== undefined) z.string().min(1).max(512).parse(attachment.nodeId);
  if (attachment.canvasPath !== undefined) {
    relativePathSchema.parse(attachment.canvasPath);
    if (getWorkspaceStore().mode === "local") {
      const resolved = await resolveWorkspacePath(cwd, attachment.canvasPath, true);
      attachment = { ...attachment, canvasPath: relative(cwd, resolved.path).replace(/\\/g, "/") };
    }
  }
  return locked(key, async () => {
    const current = await load(cwd, taskId, key, owner);
    if (current) {
      if (current.record.request && serialize({ mediaType: current.record.mediaType, request: current.record.request, nodeId: current.record.nodeId, canvasPath: current.record.canvasPath })
        !== serialize({ mediaType, request: parsed, nodeId: attachment.nodeId, canvasPath: attachment.canvasPath })) invalid("相同任务 ID 不能用于不同的生成请求", 409);
      if (current.persistenceError) await persist(current);
      if (current.record.state === "running" && !current.active && await prepareCharge(current, true)) await launch(current, false);
      await reconcileCharge(current);
      return snapshot(current, owner);
    }
    if (activeCount >= 1000) invalid("生成任务过多，请稍后重试", 429);
    const now = Date.now();
    const task: MediaTask = { key, blobs: [], active: false, record: {
      version: 1, taskId, cwd, mediaType, request: parsed, ...attachment,
      state: "running", createdAt: now, updatedAt: now, checkpoint: {},
    } };
    try {
      // SQL 预占与文件提交不能原子完成；先保留提交意图，chargeId 成功落盘后才允许调用上游。
      await persist(task, true);
      tasks.set(key, task);
      await prepareCharge(task);
      await launch(task, false);
    } catch (cause) {
      task.settledAt = Date.now();
      if (!task.active && !task.persistenceError) {
        task.record.state = "failed";
        const failure = errorFromCause(cause);
        task.record.result = { ...failure, data: null };
        await persist(task);
        await releaseCharge(task);
      }
      throw cause;
    }
    return snapshot(task, owner);
  });
}

export async function status(cwd: string, taskIds: string[], resume = false, owner?: TaskOwnerIdentity) {
  requireOwner(owner);
  cwd = await normalizeWorkspace(cwd);
  return Promise.all(taskIds.map(taskId => {
    const key = taskPath(cwd, taskId);
    return locked(key, async () => {
      const task = await load(cwd, taskId, key, owner);
      if (!task) return { taskId, state: "interrupted" as const, resumable: false, result: error<GeneratedMedia[]>("生成任务不存在", null, 404) };
      if (task.persistenceError) await persist(task);
      await reconcileCharge(task);
      if (!task.active && task.record.state === "running" && await prepareCharge(task, true)) await launch(task, false);
      if (!task.active && (task.record.state === "running" || (resume && task.record.state === "interrupted"))) {
        if (await resumable(task)) await launch(task, true);
        else {
          task.record.state = "interrupted";
          task.record.result ??= error("上次生成已中断，缺少可恢复的任务凭据，请先确认供应商任务状态", null, 409);
          await persist(task);
        }
      }
      return snapshot(task, owner);
    });
  }));
}

export async function cancel(cwd: string, taskIds: string[], owner?: TaskOwnerIdentity) {
  requireOwner(owner);
  cwd = await normalizeWorkspace(cwd);
  await Promise.all(taskIds.map(taskId => {
    const key = taskPath(cwd, taskId);
    return locked(key, async () => {
      let task = await load(cwd, taskId, key, owner);
      const now = Date.now();
      const exclusive = !task;
      if (!task) {
        task = { key, blobs: [], active: false, settledAt: now, record: {
          version: 1, taskId, cwd, ownerUserId: owner?.role === "user" ? owner.id : undefined,
          state: "cancelled", checkpoint: {}, createdAt: now, updatedAt: now,
          result: error<GeneratedMedia[]>("生成已取消", null, 499),
        } };
        tasks.set(key, task);
      } else if (["succeeded", "failed", "cancelled"].includes(task.record.state)) {
        if (task.persistenceError) await persist(task);
        await reconcileCharge(task);
        return;
      }
      task.record.state = "cancelled";
      task.record.result = error<GeneratedMedia[]>("生成已取消", null, 499);
      // 取消先落盘；包括尚未收到提交的 ID，防止乱序请求稍后创建付费任务。
      await persist(task, exclusive);
      await releaseCharge(task);
    });
  }));
}

export async function wait(cwd: string, taskId: string, owner?: TaskOwnerIdentity, signal?: AbortSignal): Promise<GeneratedMedia[]> {
  requireOwner(owner);
  if (signal?.aborted) { await cancel(cwd, [taskId], owner); signal.throwIfAborted(); }
  cwd = await normalizeWorkspace(cwd);
  const task = await load(cwd, taskId, taskPath(cwd, taskId), owner);
  if (!task) invalid("生成任务不存在", 404);
  let abort: (() => void) | undefined;
  try {
    await Promise.race([task.completion, new Promise<never>((_resolve, reject) => {
      abort = () => {
        void cancel(cwd, [taskId], owner).catch(() => { console.warn("取消媒体任务失败"); });
        reject(signal?.reason);
      };
      if (signal?.aborted) abort();
      else signal?.addEventListener("abort", abort, { once: true });
    })]);
    signal?.throwIfAborted();
    const result = task.record.result;
    if (task.record.state === "succeeded" && result?.data) return result.data;
    throw Object.assign(new Error(result?.message ?? "媒体生成失败"), { status: result?.code ?? 500, taskId });
  } finally { if (abort) signal?.removeEventListener("abort", abort); }
}

const cleanupTimer = setInterval(() => {
  const now = Date.now();
  for (const [key, task] of tasks) {
    if (!task.active && !task.persistenceError && !operations.has(key) && task.settledAt !== undefined && task.settledAt + 300000 <= now) tasks.delete(key);
  }
}, 30000);
cleanupTimer.unref();
