<template>
  <div class="loginContainer">
    <div class="loginCard">
      <h1 class="loginTitle">欢迎使用 YuYuer Drama</h1>
      <p class="loginSubtitle">使用 new-api 账号登录开始创作</p>
      <el-button type="primary" size="large" class="loginButton" @click="redirectToLogin()">
        使用 new-api 账号登录
      </el-button>
    </div>
  </div>
</template>

<script setup lang="ts">
import { redirectToLogin } from "@/lib/gatewayAuth";
</script>

<style lang="scss" scoped>
.loginContainer {
  min-height: 100vh;
  display: flex;
  align-items: center;
  justify-content: center;
  background-color: var(--el-bg-color);
}

.loginCard {
  min-width: 360px;
  max-width: 90vw;
  padding: 48px 40px;
  border-radius: 12px;
  background-color: var(--el-bg-color-overlay);
  box-shadow: var(--el-box-shadow-light);
  text-align: center;
}

.loginTitle {
  margin: 0 0 8px;
  font-size: 24px;
  font-weight: 600;
  color: var(--el-text-color-primary);
}

.loginSubtitle {
  margin: 0 0 32px;
  font-size: 14px;
  color: var(--el-text-color-secondary);
}

.loginButton {
  width: 100%;
}
</style>
