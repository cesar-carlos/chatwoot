<script>
import { useAlert } from 'dashboard/composables';
import InboxesAPI from 'dashboard/api/inboxes';
import SettingsFieldSection from 'dashboard/components-next/Settings/SettingsFieldSection.vue';
import SettingsToggleSection from 'dashboard/components-next/Settings/SettingsToggleSection.vue';
import SelectInput from 'dashboard/components-next/select/Select.vue';
import WavoipDevicePanel from 'customDashboard/routes/dashboard/settings/inbox/settingsPage/WavoipDevicePanel.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

export default {
  components: {
    SettingsFieldSection,
    SettingsToggleSection,
    SelectInput,
    WavoipDevicePanel,
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
      includeAdministrators:
        this.inbox.incoming_call_include_administrators !== false,
      notifyBusyAgents: this.inbox.incoming_call_notify_busy_agents === true,
      offlineFallback:
        this.inbox.incoming_call_offline_fallback ||
        'assignee_or_inbox_members_and_administrators',
      ringTimeoutSeconds: this.inbox.ring_timeout_seconds || 0,
      isTogglingInbound: false,
      isSavingRouting: false,
      isRegeneratingWebhook: false,
      isTestingWebhook: false,
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
    offlineFallbackOptions() {
      return [
        'none',
        'assignee',
        'assignee_or_team_members',
        'assignee_or_inbox_members',
        'assignee_or_inbox_members_and_administrators',
      ].map(value => ({
        value,
        label: this.$t(
          `INBOX_MGMT.WAVOIP_CALL.ROUTING.OFFLINE_FALLBACK.OPTIONS.${value.toUpperCase()}`
        ),
      }));
    },
    ringTimeoutOptions() {
      return [0, 10, 20, 30, 60, 90, 120].map(value => ({
        value,
        label: this.$t(
          `INBOX_MGMT.WAVOIP_CALL.ROUTING.RING_TIMEOUT.OPTIONS.${value}`
        ),
      }));
    },
    administratorsToggleDisabled() {
      return this.offlineFallback === 'none';
    },
  },
  watch: {
    'inbox.inbound_calls_enabled'(val) {
      this.inboundCallsEnabled = val !== false;
    },
    'inbox.incoming_call_include_administrators'(val) {
      this.includeAdministrators = val !== false;
    },
    'inbox.incoming_call_offline_fallback'(val) {
      if (val) this.offlineFallback = val;
    },
    'inbox.incoming_call_notify_busy_agents'(val) {
      this.notifyBusyAgents = val === true;
    },
    'inbox.ring_timeout_seconds'(val) {
      this.ringTimeoutSeconds = val || 0;
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
        await this.$store.dispatch('inboxes/fetchInboxItem', this.inbox.id);
        useAlert(this.$t('INBOX_MGMT.EDIT.API.SUCCESS_MESSAGE'));
      } catch (_) {
        this.inboundCallsEnabled = previousValue;
        useAlert(this.$t('INBOX_MGMT.EDIT.API.ERROR_MESSAGE'));
      } finally {
        this.isTogglingInbound = false;
      }
    },
    async saveCallRouting(updates) {
      if (this.isSavingRouting) return;
      this.isSavingRouting = true;
      try {
        await this.$store.dispatch('inboxes/fetchInboxItem', this.inbox.id);
        const serverInbox =
          this.$store.getters['inboxes/getInbox'](this.inbox.id) || this.inbox;
        const existing = { ...(serverInbox.provider_config || {}) };
        await this.$store.dispatch('inboxes/updateInbox', {
          id: this.inbox.id,
          formData: false,
          channel: {
            provider_config: {
              ...existing,
              incoming_call_include_administrators:
                updates.incoming_call_include_administrators,
              incoming_call_offline_fallback:
                updates.incoming_call_offline_fallback,
              incoming_call_notify_busy_agents:
                updates.incoming_call_notify_busy_agents,
              ring_timeout_seconds: updates.ring_timeout_seconds,
            },
          },
        });
        await this.$store.dispatch('inboxes/fetchInboxItem', this.inbox.id);
        useAlert(this.$t('INBOX_MGMT.EDIT.API.SUCCESS_MESSAGE'));
      } catch (_) {
        useAlert(this.$t('INBOX_MGMT.EDIT.API.ERROR_MESSAGE'));
        throw _;
      } finally {
        this.isSavingRouting = false;
      }
    },
    async handleIncludeAdministratorsToggle(newValue) {
      const previousValue = this.includeAdministrators;
      this.includeAdministrators = newValue;
      try {
        await this.saveCallRouting({
          incoming_call_include_administrators: newValue,
          incoming_call_offline_fallback: this.offlineFallback,
          incoming_call_notify_busy_agents: this.notifyBusyAgents,
          ring_timeout_seconds: this.ringTimeoutSeconds,
        });
      } catch (_) {
        this.includeAdministrators = previousValue;
      }
    },
    async handleNotifyBusyAgentsToggle(newValue) {
      const previousValue = this.notifyBusyAgents;
      this.notifyBusyAgents = newValue;
      try {
        await this.saveCallRouting({
          incoming_call_include_administrators: this.includeAdministrators,
          incoming_call_offline_fallback: this.offlineFallback,
          incoming_call_notify_busy_agents: newValue,
          ring_timeout_seconds: this.ringTimeoutSeconds,
        });
      } catch (_) {
        this.notifyBusyAgents = previousValue;
      }
    },
    async handleOfflineFallbackChange(newValue) {
      const previousValue = this.offlineFallback;
      const previousIncludeAdmins = this.includeAdministrators;
      this.offlineFallback = newValue;
      const includeAdmins =
        newValue === 'none' ? false : this.includeAdministrators;
      if (newValue === 'none') {
        this.includeAdministrators = false;
      }
      try {
        await this.saveCallRouting({
          incoming_call_include_administrators: includeAdmins,
          incoming_call_offline_fallback: newValue,
          incoming_call_notify_busy_agents: this.notifyBusyAgents,
          ring_timeout_seconds: this.ringTimeoutSeconds,
        });
      } catch (_) {
        this.offlineFallback = previousValue;
        this.includeAdministrators = previousIncludeAdmins;
      }
    },
    async handleRingTimeoutChange(newValue) {
      const previousValue = this.ringTimeoutSeconds;
      this.ringTimeoutSeconds = newValue;
      try {
        await this.saveCallRouting({
          incoming_call_include_administrators: this.includeAdministrators,
          incoming_call_offline_fallback: this.offlineFallback,
          incoming_call_notify_busy_agents: this.notifyBusyAgents,
          ring_timeout_seconds: newValue,
        });
      } catch (_) {
        this.ringTimeoutSeconds = previousValue;
      }
    },
    async testWebhook() {
      if (this.isTestingWebhook) return;
      this.isTestingWebhook = true;
      try {
        const { data } = await InboxesAPI.testWavoipWebhook(this.inbox.id);
        await this.$store.dispatch('inboxes/fetchInboxItem', this.inbox.id);
        if (data?.webhook_verified) {
          useAlert(this.$t('INBOX_MGMT.WAVOIP_CALL.WEBHOOK.TEST_SUCCESS'));
        } else {
          useAlert(this.$t('INBOX_MGMT.WAVOIP_CALL.WEBHOOK.TEST_PENDING'));
        }
      } catch (_) {
        useAlert(this.$t('INBOX_MGMT.EDIT.API.ERROR_MESSAGE'));
      } finally {
        this.isTestingWebhook = false;
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
        await this.$store.dispatch('inboxes/fetchInboxItem', this.inbox.id);
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
      <WavoipDevicePanel :inbox="inbox" />

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

      <div
        class="flex flex-col gap-4 outline outline-1 -outline-offset-1 outline-n-weak rounded-xl px-4 py-3"
      >
        <div class="flex flex-col gap-1">
          <span class="text-heading-3 text-n-slate-12">
            {{ $t('INBOX_MGMT.WAVOIP_CALL.ROUTING.LABEL') }}
          </span>
          <span class="text-body-main text-n-slate-11">
            {{ $t('INBOX_MGMT.WAVOIP_CALL.ROUTING.DESCRIPTION') }}
          </span>
        </div>

        <div
          class="relative"
          :class="{
            'pointer-events-none opacity-60':
              isSavingRouting || administratorsToggleDisabled,
          }"
        >
          <SettingsToggleSection
            :model-value="includeAdministrators"
            :header="
              $t('INBOX_MGMT.WAVOIP_CALL.ROUTING.INCLUDE_ADMINISTRATORS.LABEL')
            "
            :description="
              administratorsToggleDisabled
                ? $t(
                    'INBOX_MGMT.WAVOIP_CALL.ROUTING.INCLUDE_ADMINISTRATORS.DISABLED_HINT'
                  )
                : $t(
                    'INBOX_MGMT.WAVOIP_CALL.ROUTING.INCLUDE_ADMINISTRATORS.DESCRIPTION'
                  )
            "
            :hide-toggle="isSavingRouting || administratorsToggleDisabled"
            @update:model-value="handleIncludeAdministratorsToggle"
          >
            <template v-if="isSavingRouting" #hiddenToggle>
              <Spinner class="size-4 text-n-slate-11" />
            </template>
          </SettingsToggleSection>
        </div>

        <div
          class="relative"
          :class="{ 'pointer-events-none opacity-60': isSavingRouting }"
        >
          <SettingsToggleSection
            :model-value="notifyBusyAgents"
            :header="
              $t('INBOX_MGMT.WAVOIP_CALL.ROUTING.NOTIFY_BUSY_AGENTS.LABEL')
            "
            :description="
              $t(
                'INBOX_MGMT.WAVOIP_CALL.ROUTING.NOTIFY_BUSY_AGENTS.DESCRIPTION'
              )
            "
            :hide-toggle="isSavingRouting"
            @update:model-value="handleNotifyBusyAgentsToggle"
          >
            <template v-if="isSavingRouting" #hiddenToggle>
              <Spinner class="size-4 text-n-slate-11" />
            </template>
          </SettingsToggleSection>
        </div>

        <SettingsFieldSection
          :label="$t('INBOX_MGMT.WAVOIP_CALL.ROUTING.OFFLINE_FALLBACK.LABEL')"
          :help-text="
            $t('INBOX_MGMT.WAVOIP_CALL.ROUTING.OFFLINE_FALLBACK.DESCRIPTION')
          "
        >
          <SelectInput
            v-model="offlineFallback"
            :options="offlineFallbackOptions"
            :disabled="isSavingRouting"
            @update:model-value="handleOfflineFallbackChange"
          />
        </SettingsFieldSection>

        <SettingsFieldSection
          :label="$t('INBOX_MGMT.WAVOIP_CALL.ROUTING.RING_TIMEOUT.LABEL')"
          :help-text="
            $t('INBOX_MGMT.WAVOIP_CALL.ROUTING.RING_TIMEOUT.DESCRIPTION')
          "
        >
          <SelectInput
            v-model="ringTimeoutSeconds"
            :options="ringTimeoutOptions"
            :disabled="isSavingRouting"
            @update:model-value="handleRingTimeoutChange"
          />
        </SettingsFieldSection>
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
      <div v-if="webhookUrl" class="mt-3 flex flex-wrap gap-2">
        <NextButton
          faded
          slate
          sm
          :label="$t('INBOX_MGMT.WAVOIP_CALL.WEBHOOK.TEST')"
          :is-loading="isTestingWebhook"
          @click="testWebhook"
        />
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
