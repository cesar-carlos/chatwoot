<script setup>
import { computed, onMounted, onUnmounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useBranding } from 'shared/composables/useBranding';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import { usePwaInstallation } from 'customDashboard/composables/usePwaInstallation';
import PwaInstallationHelp from './PwaInstallationHelp.vue';

defineProps({ promotion: { type: Boolean, default: false } });
const emit = defineEmits(['dismiss']);
const { t } = useI18n();
const { replaceInstallationName } = useBranding();
const prefix = 'PROFILE_SETTINGS.FORM.NOTIFICATIONS.';
const { status, busy, promptInstall, checkInstallability } =
  usePwaInstallation();
const helpDialog = ref(null);
let mounted = true;
const message = computed(() =>
  replaceInstallationName(
    t(`${prefix}PWA_INSTALL_STATUS_${status.value.toUpperCase()}`)
  )
);
const install = async () => {
  try {
    const choice = await promptInstall();
    if (!mounted) return;
    if (choice.outcome === 'dismissed') {
      emit('dismiss');
      useAlert(t(`${prefix}PWA_INSTALL_DISMISSED`));
    }
  } catch (error) {
    if (mounted) useAlert(t(`${prefix}PWA_INSTALL_ERROR`));
  }
};
onMounted(checkInstallability);
onUnmounted(() => {
  mounted = false;
});
</script>

<template>
  <div
    class="flex flex-col items-start justify-between gap-3 rounded-xl border border-n-weak p-4 sm:flex-row sm:items-center"
  >
    <div class="flex min-w-0 flex-col gap-1">
      <span class="text-body-main text-n-slate-12">{{
        t(`${prefix}${promotion ? 'PWA_PROMOTION_TITLE' : 'PWA_INSTALL_TITLE'}`)
      }}</span>
      <span class="text-body-small text-n-slate-11" role="status">{{
        message
      }}</span>
    </div>
    <div class="flex shrink-0 flex-wrap gap-2">
      <Button
        v-if="status === 'available'"
        sm
        :label="t(`${prefix}PWA_MOBILE_INSTALL_ACTION`)"
        :disabled="busy"
        :is-loading="busy"
        @click="install"
      />
      <Button
        v-else-if="status !== 'installed'"
        sm
        :label="t(`${prefix}PWA_HOW_INSTALL_ACTION`)"
        :disabled="busy"
        @click="helpDialog.open()"
      />
      <Button
        v-if="promotion"
        sm
        ghost
        :label="t(`${prefix}PUSH_LATER_ACTION`)"
        :disabled="busy"
        @click="emit('dismiss')"
      />
    </div>
    <Dialog
      ref="helpDialog"
      width="sm"
      overflow-y-auto
      :title="t(`${prefix}PWA_HOW_INSTALL_ACTION`)"
      :show-confirm-button="false"
      :cancel-button-label="t(`${prefix}PUSH_DONE_ACTION`)"
    >
      <p
        v-if="['manifest_error', 'icon_error', 'unsupported'].includes(status)"
        class="text-body-small text-n-slate-11"
      >
        {{ message }}
      </p>
      <PwaInstallationHelp v-else />
      <Button
        v-if="promotion"
        class="mt-3"
        ghost
        :label="t(`${prefix}PUSH_LATER_ACTION`)"
        @click="
          helpDialog.close();
          emit('dismiss');
        "
      />
    </Dialog>
  </div>
</template>
