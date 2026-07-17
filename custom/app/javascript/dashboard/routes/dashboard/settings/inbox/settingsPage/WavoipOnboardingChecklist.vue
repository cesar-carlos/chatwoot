<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { normalizeWavoipDeviceStatus } from 'customDashboard/lib/wavoip/wavoipDeviceStatusNormalize';

const props = defineProps({
  inbox: {
    type: Object,
    required: true,
  },
  liveDeviceStatus: {
    type: String,
    default: null,
  },
});

const { t } = useI18n();

const WEBHOOK_STALE_MS = 24 * 60 * 60 * 1000;

function webhookStale(inbox) {
  const verified = !(inbox.wavoip_setup_pending ?? inbox.wavoipSetupPending);
  if (!verified) return false;

  const lastWebhookAt =
    inbox.provider_config?.last_webhook_at ||
    inbox.provider_config?.lastWebhookAt;
  if (!lastWebhookAt) return true;

  const parsed = Date.parse(lastWebhookAt);
  if (Number.isNaN(parsed)) return true;
  return Date.now() - parsed > WEBHOOK_STALE_MS;
}

const items = computed(() => {
  const voiceEnabled = props.inbox.voice_enabled === true;
  const hasToken = Boolean(
    props.inbox.wavoip_device_token_configured ??
      props.inbox.wavoipDeviceTokenConfigured ??
      props.inbox.provider_config?.device_token ??
      props.inbox.device_token
  );
  const webhookVerified = !(
    props.inbox.wavoip_setup_pending ?? props.inbox.wavoipSetupPending
  );
  const resolvedDeviceStatus = normalizeWavoipDeviceStatus(
    props.liveDeviceStatus ||
      props.inbox.provider_config?.device_status ||
      props.inbox.device_status
  );
  const deviceOpen = resolvedDeviceStatus === 'open';
  const inboundEnabled = props.inbox.inbound_calls_enabled !== false;
  const staleWebhook = webhookStale(props.inbox);

  return [
    {
      key: 'token',
      label: t('INBOX_MGMT.WAVOIP_ONBOARDING.TOKEN'),
      ok: hasToken,
    },
    {
      key: 'webhook',
      label: staleWebhook
        ? t('INBOX_MGMT.WAVOIP_ONBOARDING.WEBHOOK_STALE')
        : t('INBOX_MGMT.WAVOIP_ONBOARDING.WEBHOOK'),
      ok: webhookVerified && !staleWebhook,
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
