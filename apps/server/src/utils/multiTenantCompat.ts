// ACT: 兼容 stub — 桌面端继续运行旧自托管模式时需要这些导出。
// SaaS 改造后 multiTenant 包已删除，这里返回 no-op/false 行为。
// 桌面端的 hostMode/远程连接功能仍走独立的 desktop connection 逻辑。

export function isEnabled() {
  return false;
}

export async function startMultiTenantRuntime(_app: unknown, _onEnabled?: (enabled: boolean) => void) {
  // no-op: 非多租户模式下不需要启动
}

export async function stopMultiTenantRuntime(_app: unknown) {
  // no-op: 非多租户模式下不需要停止
}

export function registerHostClient(_app: unknown, _hostSecret: string) {
  // no-op: 非多租户模式下不需要注册 host client
}
