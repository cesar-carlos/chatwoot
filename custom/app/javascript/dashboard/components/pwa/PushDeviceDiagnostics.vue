<script setup>
import { computed, onUnmounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import PushPermissionHelp from './PushPermissionHelp.vue';
import PwaInstallationHelp from './PwaInstallationHelp.vue';

const props = defineProps({ device: { type: Object, required: true } });
const { t } = useI18n();
const prefix = 'PROFILE_SETTINGS.FORM.NOTIFICATIONS.';
const dialog = ref(null);
const result = ref(null);
let mounted = true;
let revision = 0;
const busy = computed(() => props.device.disabled.value);
const activity = computed(() => props.device.activity.value);
const kind = computed(() => result.value?.kind);
const display = value => {
  if (!mounted || !value) return;
  result.value = value;
  dialog.value.open();
};
const close = () => {
  revision += 1;
  result.value = null;
};
const test = async () => {
  if (busy.value) return;
  const currentRevision = revision;
  const value = await props.device.test();
  if (currentRevision === revision) display(value);
};
const inspect = async (recoverPermission = false) => {
  const currentRevision = revision;
  const value = await props.device.inspect({ recoverPermission });
  if (mounted && currentRevision === revision && value) result.value = value;
};
const activate = async () => {
  const currentRevision = revision;
  // Invoke without awaiting anything first: preserve the native permission gesture.
  const value = await props.device.activate();
  if (mounted && currentRevision === revision && value)
    result.value = {
      kind: value.status === 'subscribed' ? 'ready' : value.status,
    };
};
defineExpose({ test });
onUnmounted(() => {
  mounted = false;
});
</script>

<template>
  <Dialog
    ref="dialog"
    width="sm"
    overflow-y-auto
    :title="t(`${prefix}PUSH_TEST_ACTION`)"
    :show-confirm-button="false"
    :cancel-button-label="t(`${prefix}PUSH_DONE_ACTION`)"
    @close="close"
  >
    <div v-if="result" class="flex flex-col gap-3" aria-live="polite">
      <p
        v-if="busy && activity"
        class="m-0 text-body-small text-n-slate-11"
        role="status"
      >
        {{ t(`${prefix}PUSH_STATUS_${activity.toUpperCase()}`) }}
      </p>
      <p class="m-0 text-body-small text-n-slate-11">
        {{ t(`${prefix}PUSH_DIAGNOSTIC_${kind.toUpperCase()}`) }}
      </p>
      <div v-if="kind === 'accepted'" class="flex flex-wrap gap-2">
        <Button
          :label="t(`${prefix}PUSH_RECEIVED_ACTION`)"
          :disabled="busy"
          @click="dialog.close()"
        />
        <Button
          ghost
          :label="t(`${prefix}PUSH_NOT_RECEIVED_ACTION`)"
          :disabled="busy"
          @click="inspect()"
        />
      </div>
      <PushPermissionHelp
        v-if="['denied', 'ready'].includes(kind)"
        :busy="busy"
        @recheck="inspect(true)"
      />
      <PwaInstallationHelp v-if="kind === 'requires_install'" />
      <Button
        v-if="['default', 'opt_out', 'unsubscribed', 'error'].includes(kind)"
        :label="
          t(
            `${prefix}${kind === 'default' ? 'PUSH_ALLOW_ACTION' : 'PUSH_ACTIVATE_ACTION'}`
          )
        "
        :disabled="busy"
        :is-loading="busy"
        @click="activate"
      />
      <Button
        v-if="kind === 'missing'"
        :label="t(`${prefix}PUSH_RECOVER_ACTION`)"
        :disabled="busy"
        :is-loading="busy"
        @click="inspect(true)"
      />
      <Button
        v-if="
          ['ready', 'invalid', 'delivery', 'connection', 'timeout'].includes(
            kind
          )
        "
        :label="t(`${prefix}PUSH_TEST_ACTION`)"
        :disabled="busy"
        :is-loading="busy"
        @click="test"
      />
    </div>
  </Dialog>
</template>
