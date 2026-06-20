<script>
import { useAlert } from 'dashboard/composables';
import InboxesAPI from 'dashboard/api/inboxes';
import SettingsFieldSection from 'dashboard/components-next/Settings/SettingsFieldSection.vue';
import SettingsToggleSection from 'dashboard/components-next/Settings/SettingsToggleSection.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

export default {
  components: {
    SettingsFieldSection,
    SettingsToggleSection,
    NextButton,
    Spinner,
  },
  props: {
    inbox: {
      type: Object,
      default: () => ({}),
    },
  },
  data() {
    return {
      inboundCallsEnabled: this.inbox.inbound_calls_enabled !== false,
      isTogglingInbound: false,
      isRegeneratingWebhook: false,
      webhookUrl:
        this.inbox.wavoip_webhook_url || this.inbox.wavoipWebhookUrl || '',
    };
  },
  computed: {
    voiceEnabled() {
      return this.inbox.voice_enabled || false;
    },
    setupPending() {
      return this.inbox.wavoip_setup_pending ?? this.inbox.wavoipSetupPending;
    },
    phoneNumber() {
      return this.inbox.phone_number;
    },
    setupStatus() {
      if (this.setupPending) {
        return {
          text: this.$t('INBOX_MGMT.WAVOIP_CALL.SETUP_STATUS.PENDING'),
          icon: 'i-lucide-clock',
          color: 'text-n-amber-11',
        };
      }

      return {
        text: this.$t('INBOX_MGMT.WAVOIP_CALL.SETUP_STATUS.VERIFIED'),
        icon: 'i-lucide-circle-check',
        color: 'text-n-teal-11',
      };
    },
  },
  watch: {
    'inbox.inbound_calls_enabled'(val) {
      this.inboundCallsEnabled = val !== false;
    },
    'inbox.wavoip_webhook_url'(val) {
      if (val) this.webhookUrl = val;
    },
    'inbox.wavoipWebhookUrl'(val) {
      if (val) this.webhookUrl = val;
    },
  },
  methods: {
    async handleInboundToggle(newValue) {
      if (this.isTogglingInbound) return;
      const previousValue = this.inboundCallsEnabled;
      this.inboundCallsEnabled = newValue;
      this.isTogglingInbound = true;
      try {
        await InboxesAPI.setInboundCalls(this.inbox.id, newValue);
        await this.$store.dispatch('inboxes/get', this.inbox.id);
        useAlert(this.$t('INBOX_MGMT.EDIT.API.SUCCESS_MESSAGE'));
      } catch (_) {
        this.inboundCallsEnabled = previousValue;
        useAlert(this.$t('INBOX_MGMT.EDIT.API.ERROR_MESSAGE'));
      } finally {
        this.isTogglingInbound = false;
      }
    },
    async regenerateWebhookKey() {
      if (this.isRegeneratingWebhook) return;
      // eslint-disable-next-line no-alert
      const confirmed = window.confirm(
        this.$t('INBOX_MGMT.WAVOIP_CALL.WEBHOOK.REGENERATE_CONFIRM')
      );
      if (!confirmed) return;

      this.isRegeneratingWebhook = true;
      try {
        const { data } = await InboxesAPI.regenerateWavoipWebhookKey(
          this.inbox.id
        );
        this.webhookUrl =
          data?.wavoip_webhook_url || data?.wavoipWebhookUrl || '';
        await this.$store.dispatch('inboxes/get', this.inbox.id);
        useAlert(this.$t('INBOX_MGMT.WAVOIP_CALL.WEBHOOK.REGENERATE_SUCCESS'));
      } catch (_) {
        useAlert(this.$t('INBOX_MGMT.EDIT.API.ERROR_MESSAGE'));
      } finally {
        this.isRegeneratingWebhook = false;
      }
    },
  },
};
</script>

<template>
  <div class="flex flex-col gap-6">
    <p v-if="!voiceEnabled" class="text-sm text-n-slate-11">
      {{ $t('INBOX_MGMT.WAVOIP_CALL.VOICE_DISABLED.DESCRIPTION') }}
    </p>

    <template v-if="voiceEnabled">
      <div
        class="relative"
        :class="{ 'pointer-events-none opacity-60': isTogglingInbound }"
      >
        <SettingsToggleSection
          :model-value="inboundCallsEnabled"
          :header="$t('INBOX_MGMT.VOICE_CONFIGURATION.INBOUND.LABEL')"
          :description="
            $t('INBOX_MGMT.VOICE_CONFIGURATION.INBOUND.DESCRIPTION')
          "
          :hide-toggle="isTogglingInbound"
          @update:model-value="handleInboundToggle"
        >
          <template v-if="isTogglingInbound" #hiddenToggle>
            <Spinner class="size-4 text-n-slate-11" />
          </template>
        </SettingsToggleSection>
      </div>
    </template>

    <SettingsFieldSection
      :label="$t('INBOX_MGMT.WAVOIP_CALL.WEBHOOK.LABEL')"
      :help-text="$t('INBOX_MGMT.WAVOIP_CALL.WEBHOOK.HELP_TEXT')"
    >
      <woot-code v-if="webhookUrl" :script="webhookUrl" lang="html" />
      <p v-else class="text-sm text-n-slate-11">
        {{ $t('INBOX_MGMT.WAVOIP_CALL.WEBHOOK.UNAVAILABLE') }}
      </p>
      <div v-if="webhookUrl" class="mt-3">
        <NextButton
          faded
          slate
          sm
          :label="$t('INBOX_MGMT.WAVOIP_CALL.WEBHOOK.REGENERATE')"
          :is-loading="isRegeneratingWebhook"
          @click="regenerateWebhookKey"
        />
      </div>
    </SettingsFieldSection>

    <SettingsFieldSection
      :label="$t('INBOX_MGMT.WAVOIP_CALL.SETUP_STATUS.LABEL')"
      :help-text="$t('INBOX_MGMT.WAVOIP_CALL.SETUP_STATUS.HELP_TEXT')"
    >
      <div class="flex items-center gap-2">
        <span :class="setupStatus.icon" class="size-4" />
        <span class="text-sm" :class="setupStatus.color">
          {{ setupStatus.text }}
        </span>
      </div>
    </SettingsFieldSection>

    <SettingsFieldSection
      v-if="phoneNumber"
      :label="$t('INBOX_MGMT.WAVOIP_CALL.PHONE_NUMBER.LABEL')"
      :help-text="$t('INBOX_MGMT.WAVOIP_CALL.PHONE_NUMBER.HELP_TEXT')"
    >
      <woot-code :script="phoneNumber" lang="html" />
    </SettingsFieldSection>

    <SettingsFieldSection
      :label="$t('INBOX_MGMT.WAVOIP_CALL.HOW_IT_WORKS.LABEL')"
      :help-text="$t('INBOX_MGMT.WAVOIP_CALL.HOW_IT_WORKS.DESCRIPTION')"
    />
  </div>
</template>
