import { createHash } from "node:crypto";
import { Router } from "express";
import { z } from "zod";
import { validateFields } from "@/lib/middleware";
import { success } from "@/lib/responseFormat";
import u from "@/utils";

const maxImageSize = 20 * 1024 * 1024;
const imageFormats = { "image/png": "png", "image/jpeg": "jpg", "image/webp": "webp", "image/gif": "gif", "image/avif": "avif", "image/bmp": "bmp" };
const outputDirectory = "assets/chatImages";
const inputSchema = z.strictObject({ directory: z.string().min(1).max(4096), url: z.string().min(1).max(16384) });

function invalid(message: string, status = 400): never {
  throw Object.assign(new Error(message), { status });
}

function imageMimeType(bytes: Buffer): keyof typeof imageFormats {
  if (bytes.length >= 24 && bytes.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10])) && bytes.toString("ascii", 12, 16) === "IHDR") return "image/png";
  if (bytes.length >= 4 && bytes[0] === 255 && bytes[1] === 216 && bytes[2] === 255) return "image/jpeg";
  if (bytes.length >= 13 && /^GIF8[79]a/.test(bytes.toString("ascii", 0, 6))) return "image/gif";
  if (bytes.length >= 16 && bytes.toString("ascii", 0, 4) === "RIFF" && bytes.toString("ascii", 8, 12) === "WEBP" && /^VP8[ LX]$/.test(bytes.toString("ascii", 12, 16))) return "image/webp";
  if (bytes.length >= 26 && bytes.toString("ascii", 0, 2) === "BM") return "image/bmp";
  if (bytes.length >= 16 && bytes.toString("ascii", 4, 8) === "ftyp") {
    const end = bytes.readUInt32BE(0);
    if (end >= 16 && end <= bytes.length) {
      for (let offset = 8; offset + 4 <= end; offset += 4) if (["avif", "avis"].includes(bytes.toString("ascii", offset, offset + 4))) return "image/avif";
    }
  }
  if (/<svg(?:\s|>)/i.test(bytes.toString("utf8", 0, 512))) invalid("暂不支持网络 SVG 图片，请使用 PNG、JPEG、WebP、GIF、AVIF 或 BMP");
  return invalid("下载内容不是支持的图片，可能返回了网页或登录页面");
}

export default Router().post("/", validateFields(inputSchema.shape), async (req, res) => {
  u.mcpControl.assertAppRequest(req);
  const input = inputSchema.parse(req.body);
  const store = u.storage.getWorkspaceStore();
  const workspace = await store.resolveWorkspace(req, input.directory);
  const url = u.workspaceDownload.remoteAddress(input.url);
  const hash = createHash("sha256").update(url.href).digest("hex");
  for (const [mimeType, extension] of Object.entries(imageFormats)) {
    const existingPath = `${outputDirectory}/${hash}.${extension}`;
    const cached = await store.stat(workspace, existingPath).catch(error => {
      if ((error as NodeJS.ErrnoException).code === "ENOENT" || (error as { status?: number }).status === 404) return null;
      throw error;
    });
    if (cached?.type === "file" && cached.size > 0 && cached.size <= maxImageSize) return res.json(success({ path: existingPath, mimeType }));
  }
  const signal = AbortSignal.timeout(30000);
  const bytes = await u.workspaceDownload.downloadPublicFile(url.href, {
    signal, maxBytes: maxImageSize, label: "聊天图片", accept: "image/avif,image/webp,image/png,image/jpeg,image/gif,image/bmp",
  }).catch(error => {
    if (signal.aborted) invalid("图片下载超时（30 秒），请检查网络后重试", 504);
    if (error instanceof Error && "status" in error) throw error;
    throw Object.assign(new Error("图片下载连接失败，请检查图片地址、网络或 HTTPS 证书", { cause: error }), { status: 502 });
  });
  const mimeType = imageMimeType(bytes);
  const path = `${outputDirectory}/${hash}.${imageFormats[mimeType]}`;
  for (const folder of ["assets", outputDirectory]) {
    await store.mkdir(workspace, folder).catch(error => {
      if ((error as NodeJS.ErrnoException).code !== "EEXIST") throw error;
    });
  }
  await store.write(workspace, path, bytes);
  res.json(success({ path, mimeType }));
});
