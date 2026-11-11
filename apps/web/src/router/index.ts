import { createRouter, createWebHashHistory } from "vue-router";
import { useHelloStore } from "@/stores/hello";
import { useWorkspaceStore } from "@/stores/workspace";
import { actualPlatform } from "@/lib/platform";

const router = createRouter({
  history: createWebHashHistory(),
  routes: [
    {
      path: "/",
      redirect: () => "/hello",
    },
    {
      path: "/login",
      component: () => import("@/pages/login/index.vue"),
    },
    {
      path: "/hello",
      beforeEnter: async () => await useHelloStore().load() ? { path: "/home", replace: true } : true,
      component: () => import("@/pages/hello/index.vue"),
    },
    {
      path: "/home",
      component: () => import("@/pages/home/index.vue"),
    },
    {
      path: "/canvas",
      redirect: "/workspace",
    },
    {
      path: "/workspace",
      beforeEnter: () => !useWorkspaceStore().project ? { path: "/home", replace: true } : true,
      component: () => import("@/pages/workspace/index.vue"),
    },
  ],
});

// ACT: 非桌面端（SaaS web）强制 OAuth 登录；桌面端不受影响。
router.beforeEach(async (to) => {
  if (actualPlatform.isLocalDesktop) return true;
  const { useAuthStore } = await import("@/stores/auth");
  const authStore = useAuthStore();
  if (!authStore.initialized) await authStore.init();
  if (!authStore.user && to.path !== "/login") return { path: "/login", replace: true };
  if (authStore.user && to.path === "/login") return { path: "/home", replace: true };
  return true;
});

export default router;
