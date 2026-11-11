<template>
  <div class="gatewayAccount">
    <el-alert v-if="loadError" :title="loadError" type="error" :closable="false" show-icon />

    <div class="accountHeader">
      <div class="accountIdentity">
        <el-avatar :size="40" class="accountAvatar">
          <icon-user :size="22" aria-hidden="true" />
        </el-avatar>
        <div class="identityText">
          <span class="identityName">{{ authStore.user?.username ?? authStore.user?.sub }}</span>
          <span v-if="authStore.user?.email" class="identityEmail">{{ authStore.user.email }}</span>
        </div>
      </div>
      <el-button text :loading="quotaLoading" @click="loadQuota">
        <icon-refresh :size="16" aria-hidden="true" />
        刷新
      </el-button>
    </div>

    <div class="summaryGrid">
      <section class="summaryCard">
        <span class="summaryLabel">可用额度</span>
        <strong class="summaryValue">{{ appBalanceText }}</strong>
      </section>
      <section class="summaryCard">
        <span class="summaryLabel">累计消费</span>
        <strong class="summaryValue">{{ appUsedText }}</strong>
      </section>
      <section class="summaryCard">
        <span class="summaryLabel">平台余额</span>
        <strong class="summaryValue">{{ balanceText }}</strong>
      </section>
      <section class="summaryCard">
        <span class="summaryLabel">请求次数</span>
        <strong class="summaryValue">{{ quotaInfo?.requestCount ?? "-" }}</strong>
      </section>
    </div>

    <section class="topupSection">
      <el-radio-group v-model="paymentMethod">
        <el-radio-button value="balance">余额划转</el-radio-button>
        <el-radio-button value="waffo_pancake">在线支付</el-radio-button>
      </el-radio-group>
      <el-input-number v-model="topupAmount" :min="1" :max="1000000" :step="10" :precision="0" controls-position="right" class="topupInput" />
      <el-button type="primary" :loading="checkoutLoading" :disabled="!topupAmount" @click="startCheckout">充值</el-button>
      <span v-if="paymentMethod === 'balance'" class="topupHint">从平台余额即时划转</span>
    </section>

    <section class="logSection">
      <h3 class="sectionTitle">用量日志</h3>
      <el-table v-loading="logsLoading" :data="logItems" size="small">
        <el-table-column label="时间" width="170">
          <template #default="{ row }">{{ formatTime(row.created_at) }}</template>
        </el-table-column>
        <el-table-column prop="model_name" label="模型" min-width="160" show-overflow-tooltip />
        <el-table-column label="Tokens" width="120">
          <template #default="{ row }">{{ (row.prompt_tokens ?? 0) + (row.completion_tokens ?? 0) }}</template>
        </el-table-column>
        <el-table-column label="额度" width="110">
          <template #default="{ row }">{{ formatRowQuota(row.quota) }}</template>
        </el-table-column>
        <el-table-column label="耗时" width="90">
          <template #default="{ row }">{{ row.use_time ? `${row.use_time}s` : "-" }}</template>
        </el-table-column>
      </el-table>
      <el-pagination
        v-if="logTotal > logPageSize"
        class="logPagination"
        layout="prev, pager, next"
        :current-page="logPage"
        :page-size="logPageSize"
        :total="logTotal"
        @current-change="changeLogPage" />
    </section>

    <el-dialog v-model="checkoutVisible" title="充值" width="720px" alignCenter appendToBody @closed="loadQuota">
      <iframe v-if="checkoutUrl" :src="checkoutUrl" class="checkoutFrame" title="充值收银台" referrerpolicy="no-referrer"></iframe>
    </el-dialog>
  </div>
</template>

<script setup lang="ts">
import { computed, onMounted, ref, watch } from "vue";
import { ElMessage } from "element-plus";
import { IconRefresh, IconUser } from "@tabler/icons-vue";
import { useAuthStore } from "@/stores/auth";
import { createGatewayCheckout, fetchGatewayLogs, fetchGatewayQuota, formatQuota } from "@/lib/gatewayAccount";
import type { GatewayPaymentMethod, GatewayQuota, GatewayUsageLog } from "@/lib/gatewayAccount";

const props = defineProps<{ visible?: boolean }>();
const authStore = useAuthStore();

const quotaInfo = ref<GatewayQuota>();
const quotaLoading = ref(false);
const loadError = ref("");

const logItems = ref<GatewayUsageLog[]>([]);
const logTotal = ref(0);
const logPage = ref(1);
const logPageSize = 10;
const logsLoading = ref(false);

const topupAmount = ref<number>();
const paymentMethod = ref<GatewayPaymentMethod>("balance");
const checkoutLoading = ref(false);
const checkoutVisible = ref(false);
const checkoutUrl = ref("");

const appBalanceText = computed(() => (quotaInfo.value ? formatQuota(quotaInfo.value.appQuota, quotaInfo.value) : "-"));
const appUsedText = computed(() => (quotaInfo.value ? formatQuota(quotaInfo.value.appUsedQuota, quotaInfo.value) : "-"));
const balanceText = computed(() => (quotaInfo.value ? formatQuota(quotaInfo.value.quota, quotaInfo.value) : "-"));

async function loadQuota() {
  quotaLoading.value = true;
  try {
    quotaInfo.value = await fetchGatewayQuota();
    loadError.value = "";
  } catch (error) {
    loadError.value = error instanceof Error ? error.message : "加载账户信息失败";
  } finally {
    quotaLoading.value = false;
  }
}

async function loadLogs() {
  logsLoading.value = true;
  try {
    const page = await fetchGatewayLogs(logPage.value, logPageSize);
    logItems.value = page.items;
    logTotal.value = page.total;
  } catch (error) {
    ElMessage.error(error instanceof Error ? error.message : "加载用量日志失败");
  } finally {
    logsLoading.value = false;
  }
}

function changeLogPage(page: number) {
  logPage.value = page;
  void loadLogs();
}

async function startCheckout() {
  if (!topupAmount.value) return;
  checkoutLoading.value = true;
  try {
    const result = await createGatewayCheckout(topupAmount.value, paymentMethod.value);
    if (result.status === "success") {
      ElMessage.success("充值成功，额度已到账");
      await loadQuota();
    } else {
      checkoutUrl.value = result.checkoutUrl;
      checkoutVisible.value = true;
    }
  } catch (error) {
    ElMessage.error(error instanceof Error ? error.message : "创建充值订单失败");
  } finally {
    checkoutLoading.value = false;
  }
}

function formatRowQuota(value: number) {
  return quotaInfo.value ? formatQuota(value, quotaInfo.value) : String(value);
}

function formatTime(seconds: number) {
  return new Date(seconds * 1000).toLocaleString("zh-CN", { hour12: false });
}

watch(() => props.visible, visible => {
  if (visible) {
    void loadQuota();
    void loadLogs();
  }
});

onMounted(() => {
  void loadQuota();
  void loadLogs();
});
</script>

<style lang="scss" scoped>
.gatewayAccount {
  padding: 0 4px 24px;
  display: grid;
  gap: 16px;

  .accountHeader {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 12px;

    .accountIdentity {
      display: flex;
      align-items: center;
      gap: 12px;

      .identityText {
        display: flex;
        flex-direction: column;
        gap: 2px;

        .identityName {
          font-size: 15px;
          font-weight: 600;
          color: var(--el-text-color-primary);
        }

        .identityEmail {
          font-size: 12px;
          color: var(--el-text-color-secondary);
        }
      }
    }
  }

  .summaryGrid {
    display: grid;
    grid-template-columns: repeat(4, minmax(0, 1fr));
    gap: 12px;

    .summaryCard {
      display: flex;
      flex-direction: column;
      gap: 6px;
      padding: 16px;
      border: 1px solid var(--el-border-color-light);
      border-radius: var(--ui-radius-large);
      background: var(--el-fill-color-extra-light);

      .summaryLabel {
        font-size: 12px;
        color: var(--el-text-color-secondary);
      }

      .summaryValue {
        font-size: 20px;
        font-weight: 600;
        color: var(--el-text-color-primary);
      }
    }
  }

  .topupSection {
    display: flex;
    align-items: center;
    flex-wrap: wrap;
    gap: 10px;

    .topupInput {
      width: 180px;
    }

    .topupHint {
      font-size: 12px;
      color: var(--el-text-color-secondary);
    }
  }

  .logSection {
    display: grid;
    gap: 10px;

    .sectionTitle {
      margin: 0;
      font-size: 14px;
      font-weight: 600;
      color: var(--el-text-color-primary);
    }

    .logPagination {
      justify-content: flex-end;
    }
  }

  .checkoutFrame {
    width: 100%;
    height: 560px;
    border: 0;
  }
}
</style>
