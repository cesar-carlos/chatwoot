<script>
import { useAlert } from 'dashboard/composables';
import SettingsFieldSection from 'dashboard/components-next/Settings/SettingsFieldSection.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import { subscribeEvolutionConnection } from 'customDashboard/composables/evolution/useEvolutionConnectionCable';

const POLL_MS = 5000;

const STATUS_STYLES = {
  open: { icon: 'i-lucide-circle-check', color: 'text-n-teal-11' },
  connecting: { icon: 'i-lucide-loader-circle', color: 'text-n-amber-11' },
  close: { icon: 'i-lucide-circle-x', color: 'text-n-ruby-11' },
};

export default {
  components: {
    SettingsFieldSection,
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
      connectionStatus: 'connecting',
      phoneNumber: '',
      qrcodeBase64: '',
      isLoading: true,
      isReconnecting: false,
      isLoggingOut: false,
      isRestarting: false,
      pollTimer: null,
      unsubscribeCable: null,
    };
  },
  computed: {
    statusStyle() {
      return STATUS_STYLES[this.connectionStatus] || STATUS_STYLES.connecting;
    },
    statusLabel() {
      const key = this.connectionStatus.toUpperCase();
      return this.$t(
        `INBOX_MGMT.EVOLUTION.SETTINGS.CONNECTION_STATUS.${key}`,
        this.connectionStatus
      );
    },
    isConnected() {
      return this.connectionStatus === 'open';
    },
    showQr() {
      return !this.isConnected && this.qrcodeBase64;
    },
    isBusy() {
      return this.isReconnecting || this.isLoggingOut || this.isRestarting;
    },
  },
  mounted() {
    this.refreshConnection();
    this.startPolling();
    this.unsubscribeCable = subscribeEvolutionConnection(
      this.inbox.id,
      this.applyPayload,
      { store: this.$store }
    );
  },
  beforeUnmount() {
    this.stopPolling();
    this.unsubscribeCable?.();
  },
  methods: {
    stopPolling() {
      if (this.pollTimer) {
        clearInterval(this.pollTimer);
        this.pollTimer = null;
      }
    },
    startPolling() {
      this.stopPolling();
      this.pollTimer = setInterval(this.refreshConnection, POLL_MS);
    },
    applyPayload(payload) {
      this.connectionStatus =
        payload.connectionStatus ||
        payload.connection_status ||
        this.connectionStatus;
      this.phoneNumber = payload.phoneNumber || payload.phone_number || '';
      const qr = payload.qrcodeBase64 || payload.qrcode_base64;
      if (qr) this.qrcodeBase64 = qr;
    },
    async refreshConnection() {
      try {
        const payload = await this.$store.dispatch(
          'inboxes/fetchEvolutionConnection',
          this.inbox.id
        );
        this.applyPayload(payload);
      } catch {
        // keep last known state
      } finally {
        this.isLoading = false;
      }
    },
    async runAction(action, flag) {
      if (this[flag]) return;
      this[flag] = true;
      try {
        const payload = await this.$store.dispatch(
          `inboxes/${action}`,
          this.inbox.id
        );
        this.applyPayload(payload);
        await this.$store.dispatch('inboxes/get', this.inbox.id);
        useAlert(
          this.$t('INBOX_MGMT.EVOLUTION.SETTINGS.HEALTH.ACTION_SUCCESS')
        );
      } catch (error) {
        useAlert(
          error.response?.data?.error ||
            this.$t('INBOX_MGMT.EDIT.API.ERROR_MESSAGE')
        );
      } finally {
        this[flag] = false;
      }
    },
    async reconnect() {
      await this.runAction('evolutionReconnect', 'isReconnecting');
    },
    async restart() {
      // eslint-disable-next-line no-alert
      const confirmed = window.confirm(
        this.$t('INBOX_MGMT.EVOLUTION.SETTINGS.HEALTH.RESTART_CONFIRM')
      );
      if (!confirmed) return;
      await this.runAction('evolutionRestart', 'isRestarting');
    },
    async logout() {
      // eslint-disable-next-line no-alert
      const confirmed = window.confirm(
        this.$t('INBOX_MGMT.EVOLUTION.SETTINGS.HEALTH.LOGOUT_CONFIRM')
      );
      if (!confirmed) return;
      await this.runAction('evolutionLogout', 'isLoggingOut');
    },
  },
};
</script>

<template>
  <div class="flex flex-col gap-6">
    <SettingsFieldSection
      :label="$t('INBOX_MGMT.EVOLUTION.SETTINGS.CONNECTION_STATUS.LABEL')"
      :help-text="
        $t('INBOX_MGMT.EVOLUTION.SETTINGS.CONNECTION_STATUS.HELP_TEXT')
      "
    >
      <div
        v-if="isLoading"
        class="flex items-center gap-2 text-sm text-n-slate-11"
      >
        <Spinner class="size-4" />
        {{ $t('INBOX_MGMT.EVOLUTION.SETTINGS.HEALTH.LOADING') }}
      </div>
      <div v-else class="flex items-center gap-2">
        <span :class="[statusStyle.icon, statusStyle.color]" class="size-4" />
        <span class="text-sm" :class="statusStyle.color">{{
          statusLabel
        }}</span>
      </div>
    </SettingsFieldSection>

    <SettingsFieldSection
      v-if="phoneNumber"
      :label="$t('INBOX_MGMT.EVOLUTION.SETTINGS.HEALTH.PHONE_NUMBER.LABEL')"
      :help-text="
        $t('INBOX_MGMT.EVOLUTION.SETTINGS.HEALTH.PHONE_NUMBER.HELP_TEXT')
      "
    >
      <woot-code :script="phoneNumber" lang="html" />
    </SettingsFieldSection>

    <div v-if="showQr" class="flex flex-col items-start gap-3">
      <p class="text-sm text-n-slate-11">
        {{ $t('INBOX_MGMT.EVOLUTION.SETTINGS.HEALTH.QR.DESCRIPTION') }}
      </p>
      <div class="p-4 rounded-2xl bg-white border border-n-weak">
        <img
          :src="qrcodeBase64"
          alt="WhatsApp QR Code"
          class="w-48 h-48 object-contain"
        />
      </div>
    </div>

    <div class="flex flex-wrap gap-3">
      <NextButton
        :label="$t('INBOX_MGMT.EVOLUTION.SETTINGS.HEALTH.RECONNECT')"
        :is-loading="isReconnecting"
        :disabled="isBusy"
        @click="reconnect"
      />
      <NextButton
        faded
        slate
        :label="$t('INBOX_MGMT.EVOLUTION.SETTINGS.HEALTH.RESTART')"
        :is-loading="isRestarting"
        :disabled="isBusy"
        @click="restart"
      />
      <NextButton
        faded
        ruby
        :label="$t('INBOX_MGMT.EVOLUTION.SETTINGS.HEALTH.LOGOUT')"
        :is-loading="isLoggingOut"
        :disabled="isBusy"
        @click="logout"
      />
    </div>
  </div>
</template>
