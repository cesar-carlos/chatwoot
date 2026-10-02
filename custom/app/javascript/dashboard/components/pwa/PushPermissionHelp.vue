<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useBranding } from 'shared/composables/useBranding';
import Button from 'dashboard/components-next/button/Button.vue';
import { getPushPermissionHelpPlatform } from 'customDashboard/helper/pushPermissionHelp';

defineProps({ busy: { type: Boolean, default: false } });
const emit = defineEmits(['recheck']);
const { t } = useI18n();
const { replaceInstallationName } = useBranding();
const prefix = 'PROFILE_SETTINGS.FORM.NOTIFICATIONS.';
const platform = getPushPermissionHelpPlatform();
const site = window.location.origin;
const instruction = computed(() =>
  replaceInstallationName(t(`${prefix}PUSH_HELP_${platform}`))
);
</script>

<template>
  <div class="flex flex-col gap-3 text-body-small text-n-slate-11">
    <p class="m-0 select-text break-all">
      {{ t(`${prefix}PUSH_HELP_SITE`, { site }) }}
    </p>
    <p class="m-0">{{ instruction }}</p>
    <p class="m-0">{{ t(`${prefix}PUSH_HELP_SYSTEM`) }}</p>
    <Button
      :label="t(`${prefix}PUSH_RECHECK_ACTION`)"
      :disabled="busy"
      :is-loading="busy"
      @click="emit('recheck')"
    />
  </div>
</template>
