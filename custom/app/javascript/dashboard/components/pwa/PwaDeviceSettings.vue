<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useBranding } from 'shared/composables/useBranding';
import Button from 'dashboard/components-next/button/Button.vue';
import ToggleSwitch from 'dashboard/components-next/switch/Switch.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import PushPermissionHelp from './PushPermissionHelp.vue';
import PwaInstallationCard from './PwaInstallationCard.vue';
import PushDeviceDiagnostics from './PushDeviceDiagnostics.vue';
import { usePushDevice } from 'customDashboard/composables/usePushDevice';

const emit = defineEmits(['permissionChange']);
const { t } = useI18n();
const { replaceInstallationName } = useBranding();
const prefix = 'PROFILE_SETTINGS.FORM.NOTIFICATIONS.';
const device = usePushDevice();
const {
  status,
  permission,
  subscribed,
  endpoint,
  busy,
  disabled,
  activate,
  deactivate,
  refresh,
} = device;
const helpDialog = ref(null);
const diagnosticDialog = ref(null);
const brandedText = key => replaceInstallationName(t(key));
const pushStatusMessage = computed(() =>
  brandedText(
    `${prefix}PUSH_STATUS_${busy.value && !subscribed.value ? 'ACTIVATING' : status.value.toUpperCase()}`
  )
);
const activationLabel = computed(() => {
  if (status.value === 'error') return t(`${prefix}RETRY`);
  return t(
    `${prefix}${permission.value === 'default' ? 'PUSH_ALLOW_ACTION' : 'PUSH_ACTIVATE_ACTION'}`
  );
});
watch(permission, value => emit('permissionChange', value), {
  immediate: true,
});
</script>

<template>
  <div class="flex flex-col gap-3">
    <PwaInstallationCard />
    <div class="flex w-full flex-col gap-3 rounded-xl border border-n-weak p-4">
      <div class="flex items-center justify-between gap-3">
        <div class="flex min-w-0 items-start gap-2">
          <fluent-icon
            icon="alert"
            class="shrink-0 text-n-slate-12"
            size="18"
          />
          <div class="flex min-w-0 flex-col gap-1">
            <span class="text-body-main text-n-slate-12">
              {{ t(`${prefix}BROWSER_PERMISSION`) }}
            </span>
            <span class="text-body-small text-n-slate-11" role="status">
              {{ pushStatusMessage }}
            </span>
          </div>
        </div>
        <ToggleSwitch
          v-if="subscribed"
          model-value
          :disabled="disabled"
          :aria-label="t(`${prefix}BROWSER_PERMISSION`)"
          @change="deactivate"
        />
      </div>
      <Button
        v-if="status === 'denied'"
        sm
        :label="t(`${prefix}PUSH_HELP_ACTION`)"
        :disabled="disabled"
        @click="helpDialog.open()"
      />
      <Button
        v-else-if="['default', 'unsubscribed', 'error'].includes(status)"
        sm
        :label="activationLabel"
        :disabled="disabled"
        :is-loading="busy"
        @click="activate"
      />
      <p v-if="subscribed" class="m-0 text-body-small text-n-slate-11">
        {{ t(`${prefix}PUSH_ACTIVATED_HINT`) }}
      </p>
      <Button
        v-if="subscribed && endpoint"
        sm
        faded
        :label="t(`${prefix}PUSH_TEST_ACTION`)"
        :disabled="disabled"
        :is-loading="busy"
        @click="diagnosticDialog.test()"
      />
    </div>
    <PushDeviceDiagnostics ref="diagnosticDialog" :device="device" />
    <Dialog
      ref="helpDialog"
      width="sm"
      overflow-y-auto
      :title="t(`${prefix}PUSH_HELP_ACTION`)"
      :show-confirm-button="false"
      :cancel-button-label="t(`${prefix}PUSH_DONE_ACTION`)"
    >
      <PushPermissionHelp
        :busy="disabled"
        @recheck="refresh({ recoverPermission: true })"
      />
      <p
        v-if="subscribed"
        class="mt-3 text-body-small text-n-slate-11"
        role="status"
      >
        {{ t(`${prefix}PUSH_ACTIVATED_HINT`) }}
      </p>
    </Dialog>
  </div>
</template>
