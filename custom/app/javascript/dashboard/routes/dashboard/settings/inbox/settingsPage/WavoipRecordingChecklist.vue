<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useBranding } from 'shared/composables/useBranding';

const props = defineProps({
  inbox: {
    type: Object,
    required: true,
  },
  recordingDocsUrl: {
    type: String,
    default: 'https://wavoip.gitbook.io/api/gravacao',
  },
});

const { t } = useI18n();
const { replaceInstallationName } = useBranding();

const items = computed(() => {
  const chatwootEnabled = props.inbox.call_recording_enabled !== false;
  const webhookVerified = !(
    props.inbox.wavoip_setup_pending ?? props.inbox.wavoipSetupPending
  );

  return [
    {
      key: 'wavoip_panel',
      label: t('INBOX_MGMT.WAVOIP_RECORDING_CHECKLIST.WAVOIP_PANEL'),
      ok: null,
      manual: true,
    },
    {
      key: 'record_webhook',
      label: t('INBOX_MGMT.WAVOIP_RECORDING_CHECKLIST.RECORD_WEBHOOK'),
      ok: webhookVerified,
      manual: false,
    },
    {
      key: 'chatwoot_toggle',
      label: replaceInstallationName(
        t('INBOX_MGMT.WAVOIP_RECORDING_CHECKLIST.CHATWOOT_TOGGLE')
      ),
      ok: chatwootEnabled,
      manual: false,
    },
  ];
});

const autoReadyCount = computed(
  () => items.value.filter(item => item.ok === true).length
);
</script>

<template>
  <div
    class="flex flex-col gap-3 outline outline-1 -outline-offset-1 outline-n-weak rounded-xl px-4 py-3"
  >
    <div class="flex flex-col gap-1">
      <span class="text-heading-3 text-n-slate-12">
        {{ $t('INBOX_MGMT.WAVOIP_RECORDING_CHECKLIST.TITLE') }}
      </span>
      <span class="text-body-main text-n-slate-11">
        {{
          $t('INBOX_MGMT.WAVOIP_RECORDING_CHECKLIST.SUMMARY', {
            ready: autoReadyCount,
            total: items.length,
          })
        }}
      </span>
    </div>
    <ul class="flex flex-col gap-2">
      <li
        v-for="item in items"
        :key="item.key"
        class="flex items-start gap-2 text-sm"
      >
        <span
          class="mt-0.5 inline-flex size-5 shrink-0 items-center justify-center rounded-full"
          :class="
            item.ok === true
              ? 'bg-n-teal-3 text-n-teal-11'
              : item.manual
                ? 'bg-n-slate-3 text-n-slate-11'
                : 'bg-n-amber-3 text-n-amber-11'
          "
        >
          <span
            :class="
              item.ok === true
                ? 'i-lucide-check'
                : item.manual
                  ? 'i-lucide-external-link'
                  : 'i-lucide-clock'
            "
            class="size-3"
          />
        </span>
        <span :class="item.ok === true ? 'text-n-slate-12' : 'text-n-slate-11'">
          {{ item.label }}
        </span>
      </li>
    </ul>
    <p class="text-sm text-n-slate-11">
      {{ $t('INBOX_MGMT.WAVOIP_RECORDING_CHECKLIST.HINT') }}
      <a
        :href="recordingDocsUrl"
        class="text-n-brand underline"
        target="_blank"
        rel="noopener noreferrer"
      >
        {{ $t('INBOX_MGMT.WAVOIP_CALL.RECORDING.DOCS_LINK') }}
      </a>
    </p>
  </div>
</template>
