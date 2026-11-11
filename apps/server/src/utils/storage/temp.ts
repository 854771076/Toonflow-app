import { mkdtemp, readFile, realpath, rm, writeFile } from "@toonflow/file";
import { tmpdir } from "node:os";
import { dirname, extname, join } from "node:path";
import { getWorkspaceStore } from "@/utils/storage";
import { resolveWorkspacePath } from "@/utils/workspace/files";

const tempPrefix = "toonflowMedia";
const extensionPattern = /^\.[a-zA-Z0-9]{1,16}$/;

function fileExtension(path: string) {
  const extension = extname(path);
  return extensionPattern.test(extension) ? extension : "";
}

/** 把工作区文件下载到系统临时目录，返回本地绝对路径；调用方负责调用 cleanup */
export async function materializeWorkspaceFile(workspace: string, path: string): Promise<{ filePath: string; cleanup: () => Promise<void> }> {
  const store = getWorkspaceStore();
  if (store.mode === "local") {
    // ACT: 本地模式文件已在工作区目录，直接返回真实路径，不做无意义复制。
    const target = await resolveWorkspacePath(workspace, path);
    return { filePath: target.path, cleanup: async () => {} };
  }

  const bytes = await store.read(workspace, path);
  const temporaryRoot = await realpath(tmpdir());
  const directory = await mkdtemp(join(temporaryRoot, tempPrefix));
  const filePath = join(directory, `source${fileExtension(path)}`);
  try {
    await writeFile(filePath, bytes, { flag: "wx", mode: 0o600 });
  } catch (error) {
    await rm(directory, { recursive: true, force: true }).catch((reason: unknown) => console.warn(`清理临时媒体目录失败：${directory}`, reason));
    throw error;
  }

  let cleaned = false;
  return {
    filePath,
    cleanup: async () => {
      if (cleaned) return;
      cleaned = true;
      try {
        if (dirname(directory) !== temporaryRoot) throw new Error("临时媒体目录超出系统临时目录，已停止清理");
        await rm(directory, { recursive: true, force: true });
      } catch (error) {
        // 清理失败不能覆盖调用方的原始错误。
        console.warn(`清理临时媒体目录失败：${directory}`, error);
      }
    },
  };
}

/** 把本地临时文件写回工作区 */
export async function persistWorkspaceFile(workspace: string, path: string, filePath: string): Promise<void> {
  const store = getWorkspaceStore();
  await store.write(workspace, path, await readFile(filePath));
}
