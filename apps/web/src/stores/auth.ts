import { defineStore } from "pinia";
import { ref } from "vue";
import { fetchAuthSession, logout as gatewayLogout, type AuthUser } from "@/lib/gatewayAuth";

export const useAuthStore = defineStore("auth", () => {
  const user = ref<AuthUser | null>(null);
  const initialized = ref(false);

  async function init() {
    const session = await fetchAuthSession();
    if (session.authenticated && session.sub) {
      user.value = { sub: session.sub, username: session.username, email: session.email };
    } else {
      user.value = null;
    }
    initialized.value = true;
  }

  async function refresh() { await init(); }

  async function logout() { await gatewayLogout(); user.value = null; }

  return { user, initialized, init, refresh, logout };
});
