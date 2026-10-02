<script setup>
import { useI18n } from 'vue-i18n';
import { useBranding } from 'shared/composables/useBranding';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import {
  getInstallationPlatform,
  isEmbeddedBrowser,
} from 'customDashboard/composables/usePwaInstallation';

const { t } = useI18n();
const { replaceInstallationName } = useBranding();
const prefix = 'PROFILE_SETTINGS.FORM.NOTIFICATIONS.';
const platform = getInstallationPlatform();
const embedded = isEmbeddedBrowser();
const address = `${window.location.origin}/`;
const copyAddress = async () => {
  try {
    await navigator.clipboard.writeText(address);
    useAlert(t(`${prefix}PWA_ADDRESS_COPIED`));
  } catch (error) {
    useAlert(t(`${prefix}PWA_COPY_ERROR`));
  }
};
</script>

<template>
  <div class="flex flex-col gap-3 text-body-small text-n-slate-11">
    <template v-if="embedded">
      <p class="m-0">{{ t(`${prefix}PWA_EMBEDDED_HELP`) }}</p>
      <p class="m-0 select-text break-all">{{ address }}</p>
      <Button :label="t(`${prefix}PWA_COPY_ACTION`)" @click="copyAddress" />
    </template>
    <ol class="m-0 list-decimal space-y-2 pl-5">
      <li v-for="step in 3" :key="step">
        {{
          replaceInstallationName(t(`${prefix}PWA_HELP_${platform}_${step}`))
        }}
      </li>
    </ol>
  </div>
</template>
