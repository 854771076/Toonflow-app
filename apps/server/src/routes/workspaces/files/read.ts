import { createHash } from "node:crypto";
import { Router } from "express";
import { z } from "zod";
import u from "@/utils";
import { getReadableFileMimeType } from "@/lib/documentFormats";
import { validateFields } from "@/lib/middleware";
import { success } from "@/lib/responseFormat";

const router = Router();

const mediaContentTypes: Record<string, string> = {
  png: "image/png", jpg: "image/jpeg", jpeg: "image/jpeg", gif: "image/gif", webp: "image/webp", avif: "image/avif", bmp: "image/bmp",
  svg: "image/svg+xml", ico: "image/x-icon",
  mp4: "video/mp4", webm: "video/webm", mov: "video/quicktime", m4v: "video/x-m4v",
  mp3: "audio/mpeg", wav: "audio/wav", ogg: "audio/ogg", m4a: "audio/mp4", flac: "audio/flac", aac: "audio/aac",
  woff: "font/woff", woff2: "font/woff2", ttf: "font/ttf", otf: "font/otf", wasm: "application/wasm",
};

function contentTypeFor(path: string) {
  const name = path.split(/[\\/]/).pop() ?? path;
  const extension = name.match(/\.([^.]+)$/)?.[1]?.toLowerCase() ?? "";
  const mimeType = getReadableFileMimeType(name) ?? mediaContentTypes[extension] ?? "application/octet-stream";
  return /^text\/|^application\/(?:[\w.-]+\+)?(?:json|xml|yaml|graphql|sql)$/.test(mimeType) ? `${mimeType}; charset=utf-8` : mimeType;
}

export default router.get("/", validateFields({ directory: z.string().min(1).max(4096), path: z.string().max(4096), snapshot: z.enum(["true"]).optional(), maxBytes: z.coerce.number().int().positive().max(20 * 1024 * 1024).optional() }, "query"), async (req, res) => {
  const store = u.storage.getWorkspaceStore();
  const workspace = await store.resolveWorkspace(req, req.query.directory as string);
  const path = req.query.path as string;
  const info = await store.stat(workspace, path);
  if (info.type !== "file") throw Object.assign(new Error("只能读取文件"), { status: 400 });
  res.set("Cache-Control", "no-store");
  if (req.query.snapshot === "true") {
    const maxBytes = req.query.maxBytes === undefined ? undefined : Number(req.query.maxBytes);
    if (maxBytes !== undefined && info.size > maxBytes) throw Object.assign(new Error("文件超过本次文本读取的大小限制"), { status: 413 });
    const bytes = await store.read(workspace, path);
    if (maxBytes !== undefined && bytes.length > maxBytes) throw Object.assign(new Error("文件超过本次文本读取的大小限制"), { status: 413 });
    const encoding = bytes[0] === 0xff && bytes[1] === 0xfe ? "utf-16le"
      : bytes[0] === 0xfe && bytes[1] === 0xff ? "utf-16be"
        : bytes[0] === 0xef && bytes[1] === 0xbb && bytes[2] === 0xbf ? "utf-8-bom" : "utf-8";
    let text: string;
    try {
      text = new TextDecoder(encoding === "utf-8-bom" ? "utf-8" : encoding, { fatal: true }).decode(bytes);
      if (text.includes("\0")) throw new Error("binary");
    } catch {
      throw Object.assign(new Error("文件不是受支持的 UTF-8 或带 BOM 的 UTF-16 文本，请先用原编辑器转换编码后再打开，原文件未修改"), { status: 415 });
    }
    res.json(success({ text, encoding, revision: createHash("sha256").update(bytes).digest("hex") }));
    return;
  }
  // ACT: 整文件读入内存后发送；大文件（数百 MB 视频）会占用等量内存，后续可改为流式代理。
  const bytes = await store.read(workspace, path);
  res.set("Content-Type", contentTypeFor(path)).send(Buffer.from(bytes));
});
