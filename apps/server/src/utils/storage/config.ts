export type StorageMode = "local" | "supabase";

export interface SupabaseStorageConfig {
  url: string;
  serviceRoleKey: string;
  bucket: string;
}

export interface StorageConfig {
  mode: StorageMode;
  supabase?: SupabaseStorageConfig;
}

const defaultBucket = "toonflow-workspaces";

export function resolveStorageConfig(): StorageConfig {
  const modeValue = process.env.TOONFLOW_STORAGE_MODE?.trim();
  if (modeValue && modeValue !== "local" && modeValue !== "supabase") {
    throw new Error(`存储模式配置无效：TOONFLOW_STORAGE_MODE 只能是 local 或 supabase，当前为 ${modeValue}`);
  }

  const url = process.env.SUPABASE_URL?.trim();
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY?.trim();
  const bucket = process.env.SUPABASE_STORAGE_BUCKET?.trim();

  if (modeValue === "local") return { mode: "local" };

  if (modeValue === "supabase") {
    if (!url || !serviceRoleKey) {
      const missing = [...(!url ? ["SUPABASE_URL"] : []), ...(!serviceRoleKey ? ["SUPABASE_SERVICE_ROLE_KEY"] : [])];
      throw new Error(`Supabase 存储配置不完整，缺少环境变量：${missing.join("、")}`);
    }
    return { mode: "supabase", supabase: { url, serviceRoleKey, bucket: bucket || defaultBucket } };
  }

  // 未显式指定模式时，仅三项配置齐全才切换到 Supabase，避免只配一半时静默改变存储位置。
  if (url && serviceRoleKey && bucket) {
    return { mode: "supabase", supabase: { url, serviceRoleKey, bucket } };
  }
  return { mode: "local" };
}

/** 供工作区路径解析使用，不依赖具体存储实现，避免循环引用。 */
export function getStorageMode(): StorageMode {
  return resolveStorageConfig().mode;
}
