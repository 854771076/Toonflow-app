<template>
  <div class="workspaceMenu">
    <el-card shadow="never" :bodyStyle="{ padding: '2px 4px' }">
      <div class="menuContent">
        <el-button class="toolButton" text aria-label="退出项目" title="退出项目" @click="exitVisible = true">
          <icon-logout :size="18" aria-hidden="true" />
        </el-button>
        <el-button class="toolButton" text :aria-label="hasDesktopUpdate ? '设置，有新版本可用' : '设置'" title="设置" @click="emit('openSettings')">
          <el-badge isDot :hidden="!hasDesktopUpdate">
            <icon-settings :size="18" aria-hidden="true" />
          </el-badge>
        </el-button>
        <el-dropdown v-if="!actualPlatform.isLocalDesktop && authStore.user" trigger="click" placement="bottom-end" class="userDropdown">
          <el-button class="toolButton userButton" text aria-label="账户菜单" :title="authStore.user.username ?? authStore.user.sub">
            <el-avatar :size="20" class="userAvatar">
              <icon-user :size="15" aria-hidden="true" />
            </el-avatar>
          </el-button>
          <template #dropdown>
            <el-dropdown-menu>
              <div class="userDropdownHeader">
                <el-avatar :size="32" class="userAvatarLarge">
                  <icon-user :size="24" aria-hidden="true" />
                </el-avatar>
                <div class="userDropdownInfo">
                  <span class="userDropdownName">{{ authStore.user.username ?? authStore.user.sub }}</span>
                  <span v-if="authStore.user.email" class="userDropdownEmail">{{ authStore.user.email }}</span>
                </div>
              </div>
              <el-dropdown-item divided @click="emit('openAccount')">账户设置</el-dropdown-item>
              <el-dropdown-item @click="emit('openAccount')">充值 / 余额</el-dropdown-item>
              <el-dropdown-item v-if="gatewayPublicUrl" @click="openExternal(gatewayPublicUrl + '/app.html#/subscription')">订阅 / 套餐</el-dropdown-item>
              <el-dropdown-item divided class="logoutItem" @click="handleLogout">登出</el-dropdown-item>
            </el-dropdown-menu>
          </template>
        </el-dropdown>
      </div>
    </el-card>
    <el-dialog v-model="exitVisible" title="退出项目" width="360px" alignCenter appendToBody>
      <span>是否退出当前项目并返回首页？</span>
      <template #footer>
        <el-button @click="exitVisible = false">取消</el-button>
        <el-button type="primary" :loading="leaving" @click="exitProject">退出项目</el-button>
      </template>
    </el-dialog>
  </div>
</template>

<script setup lang="ts">
import { ref } from "vue";
import { useRouter } from "vue-router";
import { ElMessage } from "element-plus";
import { IconLogout, IconSettings, IconUser } from "@tabler/icons-vue";
import { hasDesktopUpdate } from "@/stores/desktopUpdate";
import { useAuthStore } from "@/stores/auth";
import { actualPlatform } from "@/lib/platform";

const emit = defineEmits<{ openSettings: []; openAccount: [] }>();
const router = useRouter();
const authStore = useAuthStore();
const gatewayPublicUrl = import.meta.env.VITE_GATEWAY_PUBLIC_URL ?? "";

function openExternal(url: string) {
  window.open(url, "_blank", "noopener,noreferrer");
}

const exitVisible = ref(false);
const leaving = ref(false);
const loggingOut = ref(false);

async function exitProject() {
  if (leaving.value) return;
  leaving.value = true;
  try {
    await router.push("/home");
  } finally {
    leaving.value = false;
  }
}

async function handleLogout() {
  if (loggingOut.value) return;
  loggingOut.value = true;
  try {
    await authStore.logout();
  } catch {
    loggingOut.value = false;
    ElMessage.error("登出失败，请重试");
  }
}
</script>

<style scoped lang="scss">
.workspaceMenu {
  .menuContent {
    display: flex;
    align-items: center;
    gap: 2px;

    .toolButton {
      width: 28px;
      height: 28px;
      margin: 0;
      padding: 0;
    }

    .userButton {
      width: 30px;
      height: 30px;

      .userAvatar {
        background: var(--el-color-primary-light-5);
        color: var(--el-color-primary);
      }
    }
  }
}

:global(.userDropdownHeader) {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 8px 16px 12px;
  margin-bottom: 4px;
  border-bottom: 1px solid var(--el-border-color-lighter);
}

:global(.userDropdownInfo) {
  display: flex;
  flex-direction: column;
  gap: 2px;
  min-width: 0;

  .userDropdownName {
    font-weight: 500;
    line-height: 1.4;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .userDropdownEmail {
    font-size: 12px;
    color: var(--el-text-color-secondary);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
}

:global(.logoutItem) {
  color: var(--el-color-danger);
}
</style>
