import type { Request } from "express";
import { createLocalStore } from "@/utils/storage/local";
import { createSupabaseStore } from "@/utils/storage/supabase";
import { resolveStorageConfig } from "@/utils/storage/config";

export type { StorageMode } from "@/utils/storage/config";

export interface WorkspaceEntry {
  name: string;
  path: string;
  type: "file" | "directory";
}

export interface WorkspaceStat {
  type: "file" | "directory";
  size: number;
}

export interface WorkspaceStore {
  mode: import("@/utils/storage/config").StorageMode;
  /** 归一化工作区标识：local 返回绝对目录，supabase 返回 saas/<sub>/projects 形式的逻辑前缀 */
  resolveWorkspace(req: Request, directory: string): Promise<string>;
  list(workspace: string, path: string): Promise<WorkspaceEntry[]>;
  read(workspace: string, path: string): Promise<Uint8Array>;
  write(workspace: string, path: string, data: string | Uint8Array): Promise<void>;
  remove(workspace: string, path: string, recursive: boolean): Promise<void>;
  rename(workspace: string, from: string, to: string): Promise<void>;
  mkdir(workspace: string, path: string): Promise<void>;
  stat(workspace: string, path: string): Promise<WorkspaceStat>;
  exists(workspace: string, path: string): Promise<boolean>;
}

function createWorkspaceStore(): WorkspaceStore {
  const config = resolveStorageConfig();
  return config.mode === "supabase" && config.supabase ? createSupabaseStore(config.supabase) : createLocalStore();
}

let store: WorkspaceStore | undefined;

export function initializeWorkspaceStorage(): void {
  store = createWorkspaceStore();
}

export function getWorkspaceStore(): WorkspaceStore {
  if (!store) store = createWorkspaceStore();
  return store;
}
