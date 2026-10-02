<script>
import { mapGetters } from 'vuex';
import LoadingState from './components/widgets/LoadingState.vue';
import NetworkNotification from './components/NetworkNotification.vue';
import UpdateBanner from './components/app/UpdateBanner.vue';
import ImpersonationBanner from './components/app/ImpersonationBanner.vue';
import StatusBanner from './components/app/StatusBanner.vue';
import PaymentPendingBanner from './components/app/PaymentPendingBanner.vue';
import PendingEmailVerificationBanner from './components/app/PendingEmailVerificationBanner.vue';
import LowBackupCodesBanner from './components/app/LowBackupCodesBanner.vue';
import vueActionCable from './helper/actionCable';
import { useRouter } from 'vue-router';
import { useStore } from 'dashboard/composables/store';
import WootSnackbarBox from './components/SnackbarContainer.vue';
import { setColorTheme } from './helper/themeHelper';
import { isOnOnboardingView } from 'v3/helpers/RouteHelper';
import { useAccount } from 'dashboard/composables/useAccount';
import { useFontSize } from 'dashboard/composables/useFontSize';
// FORK: white-label PWA installation and browser push lifecycle
import {
  startBrowserPushResumeSync,
  stopBrowserPushResumeSync,
  syncBrowserPush,
} from 'customDashboard/helper/pushResume';
import { initializePwaInstallation } from 'customDashboard/composables/usePwaInstallation';
// FORK: one-time, user-initiated push permission guidance in the installed PWA
import PwaPushInvitation from 'customDashboard/components/pwa/PwaPushInvitation.vue';
// FORK: shared mobile installation guidance, independent of push permission
import PwaMobileInstallPromotion from 'customDashboard/components/pwa/PwaMobileInstallPromotion.vue';
// FORK: recipient-validated notification actions and normalized route detection
import { startNotificationActions } from 'customDashboard/helper/notificationActions';
import ReconnectService from 'dashboard/helper/ReconnectService';
import { useUISettings } from 'dashboard/composables/useUISettings';

export default {
  name: 'App',

  components: {
    LoadingState,
    NetworkNotification,
    ImpersonationBanner,
    UpdateBanner,
    StatusBanner,
    PaymentPendingBanner,
    WootSnackbarBox,
    PendingEmailVerificationBanner,
    LowBackupCodesBanner,
    // FORK: keep the invitation implementation in the Custom overlay
    PwaPushInvitation,
    // FORK: implementation and per-user dismissal live in Custom
    PwaMobileInstallPromotion,
  },
  setup() {
    const router = useRouter();
    const store = useStore();
    const { accountId } = useAccount();
    // Use the font size composable (it automatically sets up the watcher)
    const { currentFontSize } = useFontSize();
    const { uiSettings } = useUISettings();

    return {
      router,
      store,
      currentAccountId: accountId,
      currentFontSize,
      uiSettings,
    };
  },
  data() {
    return {
      latestChatwootVersion: null,
      reconnectService: null,
    };
  },
  computed: {
    ...mapGetters({
      getAccount: 'accounts/getAccount',
      isRTL: 'accounts/isRTL',
      currentUser: 'getCurrentUser',
      authUIFlags: 'getAuthUIFlags',
    }),
    hideOnOnboardingView() {
      return !isOnOnboardingView(this.$route);
    },
  },

  watch: {
    currentAccountId: {
      immediate: true,
      handler() {
        if (this.currentAccountId) {
          this.initializeAccount();
        }
      },
    },
  },
  mounted() {
    this.stopNotificationActions = startNotificationActions(
      this.router,
      this.store,
      key => this.$t(key)
    );
    initializePwaInstallation();
    // FORK: refresh browser push when a suspended mobile PWA becomes visible again
    startBrowserPushResumeSync();
    this.initializeColorTheme();
    this.listenToThemeChanges();
    // If user locale is set, use it; otherwise use account locale
    this.setLocale(
      this.uiSettings?.locale || window.chatwootConfig.selectedLocale
    );
  },
  unmounted() {
    this.stopNotificationActions?.();
    stopBrowserPushResumeSync();
    if (this.reconnectService) {
      this.reconnectService.disconnect();
    }
  },
  methods: {
    initializeColorTheme() {
      setColorTheme(window.matchMedia('(prefers-color-scheme: dark)').matches);
    },
    listenToThemeChanges() {
      const mql = window.matchMedia('(prefers-color-scheme: dark)');
      mql.onchange = e => setColorTheme(e.matches);
    },
    setLocale(locale) {
      if (locale) {
        this.$root.$i18n.locale = locale;
      }
    },
    async initializeAccount() {
      await this.$store.dispatch('accounts/get');
      this.$store.dispatch('setActiveAccount', {
        accountId: this.currentAccountId,
      });
      const account = this.getAccount(this.currentAccountId);
      const { locale, latest_chatwoot_version: latestChatwootVersion } =
        account;
      const { pubsub_token: pubsubToken } = this.currentUser || {};
      // If user locale is set, use it; otherwise use account locale
      this.setLocale(this.uiSettings?.locale || locale);
      this.latestChatwootVersion = latestChatwootVersion;
      vueActionCable.init(this.store, pubsubToken, this.$root.$i18n);
      this.reconnectService = new ReconnectService(this.store, this.router);
      window.reconnectService = this.reconnectService;

      // FORK: restore granted browser push subscriptions after mobile suspension
      syncBrowserPush();
    },
  },
};
</script>

<template>
  <div
    v-if="!authUIFlags.isFetching"
    id="app"
    class="flex flex-col w-full h-screen min-h-0 bg-n-background"
    :dir="isRTL ? 'rtl' : 'ltr'"
  >
    <ImpersonationBanner />
    <UpdateBanner :latest-chatwoot-version="latestChatwootVersion" />
    <StatusBanner />
    <template v-if="currentAccountId">
      <PendingEmailVerificationBanner v-if="hideOnOnboardingView" />
      <PaymentPendingBanner v-if="hideOnOnboardingView" />
      <LowBackupCodesBanner v-if="hideOnOnboardingView" />
      <!-- FORK: promote installation only outside standalone/onboarding -->
      <PwaMobileInstallPromotion
        :key="currentUser?.id"
        :user="currentUser"
        :account-id="currentAccountId"
        :ready="
          hideOnOnboardingView && Boolean(getAccount(currentAccountId)?.id)
        "
      />
      <!-- FORK: never request native permission automatically on app launch -->
      <PwaPushInvitation
        :key="currentUser?.id"
        :user="currentUser"
        :account-id="currentAccountId"
        :ready="
          hideOnOnboardingView && Boolean(getAccount(currentAccountId)?.id)
        "
      />
    </template>
    <router-view v-slot="{ Component }">
      <transition name="fade" mode="out-in">
        <component :is="Component" />
      </transition>
    </router-view>
    <WootSnackbarBox />
    <NetworkNotification />
  </div>
  <LoadingState v-else />
</template>

<style lang="scss">
@import './assets/scss/app';

.v-popper--theme-tooltip .v-popper__inner {
  background: black !important;
  font-size: 0.75rem;
  padding: 4px 8px !important;
  border-radius: 6px;
  font-weight: 400;
}

.v-popper--theme-tooltip .v-popper__arrow-container {
  display: none;
}
</style>
