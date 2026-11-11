import { createApp, type App } from "vue";
import { createPinia } from "pinia";
import { createPersistedState } from "pinia-plugin-persistedstate";
import { actualPlatform } from "@/lib/platform";

export async function createCreationApp(): Promise<App<Element>> {
  // ACT: 创作端的模块会注册设备轮询和 MCP 等能力；确认身份后才加载，登录页不接触全局设置。
  const [
    { default: appRoot }, { default: router }, { loadSettings, settingsStorage }, { registerLanguage },
    { registerAnonymousData }, { registerDownloads }, { registerDesktopProtocol }, { registerDesktopAutoUpdate },
  ] = await Promise.all([
    import("@/App.vue"), import("@/router"), import("@/stores/settings"), import("@/lib/i18n"),
    import("@/lib/anonymousData"), import("@/lib/saveFile"), import("@/lib/desktopProtocol"), import("@/stores/desktopUpdate"),
  ]);
  await loadSettings();
  const app = createApp(appRoot);
  app.onUnmount(registerLanguage());
  app.use(createPinia().use(createPersistedState({ storage: settingsStorage })));
  // ACT: 非桌面端（SaaS web）走 OAuth，需要在 router 守卫启动前完成 session 检查。
  if (!actualPlatform.isLocalDesktop) {
    const { useAuthStore } = await import("@/stores/auth");
    await useAuthStore().init();
  }
  app.use(router);
  await router.isReady();
  app.onUnmount(registerAnonymousData());
  app.onUnmount(registerDownloads());
  if (actualPlatform.isLocalDesktop) {
    app.onUnmount(registerDesktopProtocol());
    app.onUnmount(registerDesktopAutoUpdate());
  }
  return app;
}
