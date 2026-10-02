<script setup>
import { computed, ref, reactive, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import PushPermissionHelp from './PushPermissionHelp.vue';
import { usePushDevice } from 'customDashboard/composables/usePushDevice';
import { usePwaPushInvitation } from 'customDashboard/composables/usePwaPushInvitation';

const props = defineProps({
  user: { type: Object, default: () => ({}) },
  accountId: { type: [Number, String], default: null },
  ready: { type: Boolean, default: false },
});
const { t } = useI18n();
const router = useRouter();
const prefix = 'PROFILE_SETTINGS.FORM.NOTIFICATIONS.';
const device = usePushDevice();
const { status, permission, subscribed, busy, disabled, activate, refresh } =
  device;
const context = reactive({
  user: computed(() => props.user),
  accountId: computed(() => props.accountId),
  ready: computed(() => props.ready),
});
const { open, close } = usePwaPushInvitation(context, status);
const dialog = ref(null);
const showHelp = ref(false);
const primaryLabel = computed(() => {
  if (status.value === 'denied') return 'PUSH_HELP_ACTION';
  if (status.value === 'error') return 'RETRY';
  return permission.value === 'default'
    ? 'PUSH_ALLOW_ACTION'
    : 'PUSH_ACTIVATE_ACTION';
});
const primaryAction = () => {
  if (status.value === 'denied') showHelp.value = true;
  else activate();
};
const chooseEvents = () => {
  close();
  router.push({
    name: 'profile_settings_index',
    params: { accountId: props.accountId },
    hash: '#profile-settings-notifications',
  });
};
watch(open, value => {
  if (value) dialog.value?.open();
  else dialog.value?.close();
});
</script>

<template>
  <Dialog
    ref="dialog"
    width="sm"
    overflow-y-auto
    :title="t(`${prefix}PUSH_INVITATION_TITLE`)"
    :description="t(`${prefix}PUSH_INVITATION_DESCRIPTION`)"
    :show-confirm-button="false"
    :show-cancel-button="false"
    @close="close"
  >
    <div class="flex flex-col gap-3" aria-live="polite">
      <p v-if="status === 'denied'" class="m-0 text-body-small text-n-slate-11">
        {{ t(`${prefix}PUSH_STATUS_DENIED`) }}
      </p>
      <p v-if="status === 'error'" class="m-0 text-body-small text-n-slate-11">
        {{ t(`${prefix}PUSH_SUBSCRIPTION_ERROR`) }}
      </p>
      <p v-if="subscribed" class="m-0 text-body-small text-n-slate-11">
        {{ t(`${prefix}PUSH_ACTIVATED_HINT`) }}
      </p>
      <PushPermissionHelp
        v-if="showHelp && !subscribed"
        :busy="disabled"
        @recheck="refresh({ recoverPermission: true })"
      />
    </div>
    <template #footer>
      <div class="flex w-full flex-col gap-2">
        <Button
          v-if="subscribed"
          :label="t(`${prefix}PUSH_CHOOSE_EVENTS_ACTION`)"
          @click="chooseEvents"
        />
        <Button
          v-else-if="!showHelp || status !== 'denied'"
          :label="t(`${prefix}${primaryLabel}`)"
          :disabled="disabled"
          :is-loading="busy"
          @click="primaryAction"
        />
        <Button
          faded
          color="slate"
          :label="
            t(
              `${prefix}${subscribed ? 'PUSH_DONE_ACTION' : 'PUSH_LATER_ACTION'}`
            )
          "
          @click="close"
        />
      </div>
    </template>
  </Dialog>
</template>
