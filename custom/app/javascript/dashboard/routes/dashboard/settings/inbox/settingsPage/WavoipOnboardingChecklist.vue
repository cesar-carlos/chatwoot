<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  inbox: {
    type: Object,
    required: true,
  },
});

const { t } = useI18n();

const items = computed(() => {
  const voiceEnabled = props.inbox.voice_enabled === true;
  const hasToken = Boolean(
    props.inbox.provider_config?.device_token || props.inbox.device_token
  );
  const webhookVerified = !(
    props.inbox.wavoip_setup_pending ?? props.inbox.wavoipSetupPending
  );
  const deviceOpen =
    (props.inbox.provider_config?.device_status ||
      props.inbox.device_status) === 'open';
  const inboundEnabled = props.inbox.inbound_calls_enabled !== false;

  return [
    {
      key: 'token',
      label: t('INBOX_MGMT.WAVOIP_ONBOARDING.TOKEN'),
      ok: hasToken,
    },
    {
      key: 'webhook',
      label: t('INBOX_MGMT.WAVOIP_ONBOARDING.WEBHOOK'),
      ok: webhookVerified,
    },
    {
      key: 'device',
      label: t('INBOX_MGMT.WAVOIP_ONBOARDING.DEVICE_OPEN'),
      ok: deviceOpen,
    },
    {
      key: 'voice',
      label: t('INBOX_MGMT.WAVOIP_ONBOARDING.VOICE_ENABLED'),
      ok: voiceEnabled,
    },
    {
      key: 'inbound',
      label: t('INBOX_MGMT.WAVOIP_ONBOARDING.INBOUND_ENABLED'),
      ok: inboundEnabled,
    },
  ];
});

const readyCount = computed(() => items.value.filter(item => item.ok).length);
</script>

<template>
  <div
    class="flex flex-col gap-3 outline outline-1 -outline-offset-1 outline-n-weak rounded-xl px-4 py-3"
  >
    <div class="flex flex-col gap-1">
      <span class="text-heading-3 text-n-slate-12">
        {{ $t('INBOX_MGMT.WAVOIP_ONBOARDING.TITLE') }}
      </span>
      <span class="text-body-main text-n-slate-11">
        {{
          $t('INBOX_MGMT.WAVOIP_ONBOARDING.SUMMARY', {
            ready: readyCount,
            total: items.length,
          })
        }}
      </span>
    </div>
    <ul class="flex flex-col gap-2">
      <li
        v-for="item in items"
        :key="item.key"
        class="flex items-center gap-2 text-sm"
      >
        <span
          class="inline-flex size-5 items-center justify-center rounded-full"
          :class="
            item.ok
              ? 'bg-n-teal-3 text-n-teal-11'
              : 'bg-n-amber-3 text-n-amber-11'
          "
        >
          <span
            :class="item.ok ? 'i-lucide-check' : 'i-lucide-clock'"
            class="size-3"
          />
        </span>
        <span :class="item.ok ? 'text-n-slate-12' : 'text-n-slate-11'">
          {{ item.label }}
        </span>
      </li>
    </ul>
  </div>
</template>
