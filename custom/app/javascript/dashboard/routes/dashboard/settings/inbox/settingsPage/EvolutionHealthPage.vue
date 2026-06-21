<script>
import { useAlert } from 'dashboard/composables';
import SettingsFieldSection from 'dashboard/components-next/Settings/SettingsFieldSection.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import EvolutionQrScanModal from 'customDashboard/components/evolution/EvolutionQrScanModal.vue';
import { subscribeEvolutionConnection } from 'customDashboard/composables/evolution/useEvolutionConnectionCable';
import {
  normalizeEvolutionConnectionPayload,
  isEvolutionPlaceholderPhone,
} from 'customDashboard/lib/evolution/evolutionConnectionPayload';

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
    EvolutionQrScanModal,
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
      isLoading: true,
      isLoggingOut: false,
      isRestarting: false,
      isQrModalOpen: false,
      qrModalFetchFresh: false,
      pollTimer: null,
      unsubscribeCable: null,
      confirmTitle: '',
      confirmDescription: '',
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
    isBusy() {
      return this.isLoggingOut || this.isRestarting;
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
    applyPhoneFromPayload(payload, normalized) {
      const phone =
        normalized.phoneNumber || payload.phoneNumber || payload.phone_number;
      if (phone && !isEvolutionPlaceholderPhone(phone)) {
        this.phoneNumber = phone;
      }
    },
    async applyPayload(payload) {
      const normalized = normalizeEvolutionConnectionPayload(payload) || {};

      if (normalized.connectionStatus) {
        const wasConnected = this.isConnected;
        this.connectionStatus = normalized.connectionStatus;

        if (this.isConnected && !wasConnected) {
          try {
            const full = await this.$store.dispatch(
              'inboxes/fetchEvolutionConnection',
              this.inbox.id
            );
            this.applyPhoneFromPayload(
              full,
              normalizeEvolutionConnectionPayload(full) || {}
            );
          } catch {
            this.applyPhoneFromPayload(payload, normalized);
          }
          this.stopPolling();
          this.isQrModalOpen = false;
        }
      }

      this.applyPhoneFromPayload(payload, normalized);
    },
    async refreshConnection() {
      try {
        const payload = await this.$store.dispatch(
          'inboxes/fetchEvolutionConnection',
          this.inbox.id
        );
        await this.applyPayload(payload);
      } catch {
        // keep last known state
      } finally {
        this.isLoading = false;
      }
    },
    openQrModal({ fresh = false } = {}) {
      this.qrModalFetchFresh = fresh;
      this.isQrModalOpen = true;
    },
    async onQrConnected() {
      await this.$store.dispatch('inboxes/get', this.inbox.id);
      await this.refreshConnection();
    },
    async runAction(action, flag) {
      if (this[flag]) return;
      this[flag] = true;
      try {
        const payload = await this.$store.dispatch(
          `inboxes/${action}`,
          this.inbox.id
        );
        await this.applyPayload(payload);
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
    async showConfirm(title, description) {
      this.confirmTitle = title;
      this.confirmDescription = description;
      return this.$refs.confirmDialog.showConfirmation();
    },
    reconnect() {
      this.openQrModal({ fresh: true });
    },
    async restart() {
      const ok = await this.showConfirm(
        this.$t('INBOX_MGMT.EVOLUTION.SETTINGS.HEALTH.RESTART'),
        this.$t('INBOX_MGMT.EVOLUTION.SETTINGS.HEALTH.RESTART_CONFIRM')
      );
      if (!ok) return;
      await this.runAction('evolutionRestart', 'isRestarting');
      this.openQrModal({ fresh: true });
    },
    async logout() {
      const ok = await this.showConfirm(
        this.$t('INBOX_MGMT.EVOLUTION.SETTINGS.HEALTH.LOGOUT'),
        this.$t('INBOX_MGMT.EVOLUTION.SETTINGS.HEALTH.LOGOUT_CONFIRM')
      );
      if (!ok) return;
      await this.runAction('evolutionLogout', 'isLoggingOut');
      this.phoneNumber = '';
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
      v-if="phoneNumber && isConnected"
      :label="$t('INBOX_MGMT.EVOLUTION.SETTINGS.HEALTH.PHONE_NUMBER.LABEL')"
      :help-text="
        $t('INBOX_MGMT.EVOLUTION.SETTINGS.HEALTH.PHONE_NUMBER.HELP_TEXT')
      "
    >
      <woot-code :script="phoneNumber" lang="html" />
    </SettingsFieldSection>

    <div class="flex flex-wrap gap-3">
      <NextButton
        v-if="!isConnected"
        :label="$t('INBOX_MGMT.EVOLUTION.SETTINGS.HEALTH.RECONNECT')"
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

    <EvolutionQrScanModal
      v-model="isQrModalOpen"
      :inbox-id="inbox.id"
      :fetch-fresh-qr="qrModalFetchFresh"
      @connected="onQrConnected"
    />

    <woot-confirm-modal
      ref="confirmDialog"
      :title="confirmTitle"
      :description="confirmDescription"
    />
  </div>
</template>
