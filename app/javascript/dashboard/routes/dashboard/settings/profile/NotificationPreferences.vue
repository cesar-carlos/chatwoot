<script>
import { mapGetters } from 'vuex';
import { useAlert } from 'dashboard/composables';
import { useBranding } from 'shared/composables/useBranding';
import TableHeaderCell from 'dashboard/components/widgets/TableHeaderCell.vue';
import CheckBox from 'v3/components/Form/CheckBox.vue';
import {
  ensurePushSubscription,
  getPushEnvironment,
  requestAndSubscribe,
  unsubscribePush,
} from 'dashboard/helper/pushHelper.js';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import ToggleSwitch from 'dashboard/components-next/switch/Switch.vue';
import { NOTIFICATION_TYPES } from './constants';
// FORK: in-app popup notification preferences
import {
  popupFlagsForSettings,
  requestPopupNotificationPermission,
  supportsPopupNotificationType,
  withPopupFlagsForAccount,
} from 'customDashboard/composables/usePopupNotifications';

export default {
  components: {
    TableHeaderCell,
    ToggleSwitch,
    CheckBox,
  },
  setup() {
    const { replaceInstallationName } = useBranding();
    return {
      replaceInstallationName,
    };
  },
  data() {
    return {
      selectedEmailFlags: [],
      selectedPushFlags: [],
      selectedPopupFlags: [],
      enableAudioAlerts: false,
      hasEnabledPushPermissions: false,
      notificationTypes: NOTIFICATION_TYPES,
      pushStatus: getPushEnvironment().status,
    };
  },
  computed: {
    ...mapGetters({
      accountId: 'getCurrentAccountId',
      emailFlags: 'userNotificationSettings/getSelectedEmailFlags',
      pushFlags: 'userNotificationSettings/getSelectedPushFlags',
      uiSettings: 'getUISettings',
      isFeatureEnabledonAccount: 'accounts/isFeatureEnabledonAccount',
    }),
    isPushToggleDisabled() {
      return ['unsupported', 'requires_install'].includes(this.pushStatus);
    },
    pushStatusMessage() {
      const statusKeys = {
        unsupported: 'PUSH_STATUS_UNSUPPORTED',
        requires_install: 'PUSH_STATUS_REQUIRES_INSTALL',
        default: 'PUSH_STATUS_DEFAULT',
        denied: 'PUSH_STATUS_DENIED',
        subscribed: 'PUSH_STATUS_SUBSCRIBED',
        unsubscribed: 'PUSH_STATUS_UNSUBSCRIBED',
        error: 'PUSH_STATUS_ERROR',
      };
      const key = statusKeys[this.pushStatus] || statusKeys.error;
      return this.replaceInstallationName(
        this.$t(`PROFILE_SETTINGS.FORM.NOTIFICATIONS.${key}`)
      );
    },
    showIosPwaHint() {
      return this.pushStatus === 'requires_install';
    },
    isSLAEnabled() {
      return this.isFeatureEnabledonAccount(this.accountId, FEATURE_FLAGS.SLA);
    },
    filteredNotificationTypes() {
      return this.notificationTypes.filter(notification =>
        this.isSLAEnabled
          ? true
          : ![
              'sla_missed_first_response',
              'sla_missed_next_response',
              'sla_missed_resolution',
            ].includes(notification.value)
      );
    },
    // FORK: voice calls already open a dedicated incoming-call popup
    popupNotificationTypes() {
      return this.filteredNotificationTypes.filter(notification =>
        supportsPopupNotificationType(notification.value)
      );
    },
  },
  watch: {
    emailFlags(value) {
      this.selectedEmailFlags = value;
    },
    pushFlags(value) {
      this.selectedPushFlags = value;
    },
    // FORK: popup flags live in ui_settings, scoped to the active account
    uiSettings: {
      immediate: true,
      handler() {
        this.syncPopupFlags();
      },
    },
    accountId() {
      this.syncPopupFlags();
    },
  },
  mounted() {
    this.refreshPushSubscription();
    this.$store.dispatch('userNotificationSettings/get');
  },
  methods: {
    syncPopupFlags() {
      this.selectedPopupFlags = popupFlagsForSettings(
        this.uiSettings,
        this.accountId
      );
    },
    canSelectPopup(notification) {
      return supportsPopupNotificationType(notification.value);
    },
    checkFlagStatus(type, flagType) {
      const selectedFlags = {
        email: this.selectedEmailFlags,
        push: this.selectedPushFlags,
        popup: this.selectedPopupFlags,
      }[type];
      return (selectedFlags || []).includes(`${type}_${flagType}`);
    },
    async refreshPushSubscription() {
      const environment = getPushEnvironment();
      this.pushStatus = environment.status;
      this.hasEnabledPushPermissions = false;

      if (!environment.supported || environment.permission !== 'granted') {
        return;
      }

      try {
        const result = await ensurePushSubscription();
        this.pushStatus = result.status;
        this.hasEnabledPushPermissions = result.status === 'subscribed';
      } catch (error) {
        this.pushStatus = 'error';
      }
    },
    async onRequestPermissions(value) {
      const previousValue = !value;

      try {
        const result = value
          ? await requestAndSubscribe()
          : await unsubscribePush();
        this.pushStatus = result.status;
        this.hasEnabledPushPermissions = result.status === 'subscribed';

        if (result.serverError) {
          useAlert(
            this.$t(
              'PROFILE_SETTINGS.FORM.NOTIFICATIONS.PUSH_UNSUBSCRIBE_ERROR'
            )
          );
        }
      } catch (error) {
        this.pushStatus = 'error';
        this.hasEnabledPushPermissions = previousValue;
        useAlert(
          this.$t('PROFILE_SETTINGS.FORM.NOTIFICATIONS.PUSH_SUBSCRIPTION_ERROR')
        );
      }
    },
    async updateNotificationSettings(previousEmailFlags, previousPushFlags) {
      try {
        await this.$store.dispatch('userNotificationSettings/update', {
          selectedEmailFlags: this.selectedEmailFlags,
          selectedPushFlags: this.selectedPushFlags,
        });
        useAlert(this.$t('PROFILE_SETTINGS.FORM.API.UPDATE_SUCCESS'));
      } catch (error) {
        this.selectedEmailFlags = previousEmailFlags;
        this.selectedPushFlags = previousPushFlags;
        useAlert(this.$t('PROFILE_SETTINGS.FORM.API.UPDATE_ERROR'));
      }
    },
    handleInput(type, id) {
      if (type === 'email') {
        this.handleEmailInput(id);
      } else if (type === 'push') {
        this.handlePushInput(id);
      } else if (type === 'popup') {
        this.handlePopupInput(id);
      }
    },
    async handleEmailInput(id) {
      const previousEmailFlags = [...this.selectedEmailFlags];
      const previousPushFlags = [...this.selectedPushFlags];
      this.selectedEmailFlags = this.toggleInput(this.selectedEmailFlags, id);
      await this.updateNotificationSettings(
        previousEmailFlags,
        previousPushFlags
      );
    },
    async handlePushInput(id) {
      const previousEmailFlags = [...this.selectedEmailFlags];
      const previousPushFlags = [...this.selectedPushFlags];
      this.selectedPushFlags = this.toggleInput(this.selectedPushFlags, id);
      await this.updateNotificationSettings(
        previousEmailFlags,
        previousPushFlags
      );
    },
    // FORK: persist popup flags in ui_settings and request Notification permission
    async handlePopupInput(id) {
      const isEnabling = !this.selectedPopupFlags.includes(id);
      if (isEnabling) {
        const permission = await requestPopupNotificationPermission();
        if (permission !== 'granted') {
          useAlert(
            this.$t(
              'PROFILE_SETTINGS.FORM.NOTIFICATIONS.POPUP_PERMISSION_ERROR'
            )
          );
          return;
        }
      }
      const previousPopupFlags = [...this.selectedPopupFlags];
      this.selectedPopupFlags = this.toggleInput(this.selectedPopupFlags, id);
      try {
        await this.$store.dispatch('updateUISettings', {
          uiSettings: withPopupFlagsForAccount(
            this.uiSettings,
            this.accountId,
            this.selectedPopupFlags
          ),
        });
        useAlert(this.$t('PROFILE_SETTINGS.FORM.API.UPDATE_SUCCESS'));
      } catch (error) {
        this.selectedPopupFlags = previousPopupFlags;
        useAlert(this.$t('PROFILE_SETTINGS.FORM.API.UPDATE_ERROR'));
      }
    },
    toggleInput(selected, current) {
      if (selected.includes(current)) {
        const newSelectedFlags = selected.filter(flag => flag !== current);
        return newSelectedFlags;
      }
      return [...selected, current];
    },
  },
};
</script>

<template>
  <div id="profile-settings-notifications" class="flex flex-col gap-6">
    <p
      v-if="showIosPwaHint"
      class="rounded-lg border border-n-amber-6 bg-n-amber-2 px-4 py-3 text-sm text-n-amber-12"
    >
      {{
        replaceInstallationName(
          $t('PROFILE_SETTINGS.FORM.NOTIFICATIONS.IOS_PWA_HINT')
        )
      }}
    </p>
    <p
      class="rounded-lg border border-n-slate-6 bg-n-solid-2 px-4 py-3 text-sm text-n-slate-11"
    >
      {{ $t('PROFILE_SETTINGS.FORM.NOTIFICATIONS.DELIVERY_MODES_HINT') }}
    </p>
    <!-- Layout for desktop devices -->
    <div class="hidden sm:block">
      <div
        class="grid content-center h-12 grid-cols-12 gap-4 py-0 rounded-t-xl"
      >
        <TableHeaderCell
          :span="6"
          label="`${$t('PROFILE_SETTINGS.FORM.NOTIFICATIONS.TYPE_TITLE')}`"
        >
          <span class="text-heading-3 normal-case text-n-slate-12">
            {{ $t('PROFILE_SETTINGS.FORM.NOTIFICATIONS.TYPE_TITLE') }}
          </span>
        </TableHeaderCell>
        <TableHeaderCell
          :span="2"
          label="`${$t('PROFILE_SETTINGS.FORM.NOTIFICATIONS.EMAIL')}`"
        >
          <span class="text-heading-3 normal-case text-n-slate-12">
            {{ $t('PROFILE_SETTINGS.FORM.NOTIFICATIONS.EMAIL') }}
          </span>
        </TableHeaderCell>
        <TableHeaderCell
          :span="2"
          label="`${$t('PROFILE_SETTINGS.FORM.NOTIFICATIONS.PUSH')}`"
        >
          <div class="flex items-center justify-between gap-1">
            <span
              class="text-heading-3 normal-case text-n-slate-12 whitespace-nowrap"
            >
              {{ $t('PROFILE_SETTINGS.FORM.NOTIFICATIONS.PUSH') }}
            </span>
          </div>
        </TableHeaderCell>
        <!-- FORK: popup visual alerts column -->
        <TableHeaderCell
          :span="2"
          label="`${$t('PROFILE_SETTINGS.FORM.NOTIFICATIONS.POPUP')}`"
        >
          <span
            class="text-heading-3 normal-case text-n-slate-12 whitespace-nowrap"
          >
            {{ $t('PROFILE_SETTINGS.FORM.NOTIFICATIONS.POPUP') }}
          </span>
        </TableHeaderCell>
      </div>
      <div
        v-for="(notification, index) in filteredNotificationTypes"
        :key="index"
      >
        <div
          class="grid items-center content-center h-12 grid-cols-12 gap-4 py-0 rounded-t-xl"
        >
          <div
            class="flex flex-row items-start gap-2 col-span-6 px-0 py-2 text-sm tracking-[0.5] rtl:text-right"
          >
            <span class="text-body-main text-n-slate-12">
              {{ $t(notification.label) }}
            </span>
          </div>
          <div
            v-for="type in ['email', 'push', 'popup']"
            :key="type"
            class="flex items-start col-span-2 gap-2 px-0 text-sm tracking-[0.5] text-left rtl:text-right"
          >
            <CheckBox
              v-if="type !== 'popup' || canSelectPopup(notification)"
              :value="`${type}_${notification.value}`"
              :is-checked="checkFlagStatus(type, notification.value)"
              @update="id => handleInput(type, id)"
            />
            <span
              v-else
              class="text-body-main text-n-slate-11"
              :title="
                $t('PROFILE_SETTINGS.FORM.NOTIFICATIONS.POPUP_VOICE_NOTE')
              "
            >
              —
            </span>
          </div>
        </div>
      </div>
      <p class="pt-2 text-body-main text-n-slate-11">
        {{ $t('PROFILE_SETTINGS.FORM.NOTIFICATIONS.POPUP_VOICE_NOTE') }}
      </p>
    </div>
    <!--  Layout for mobile devices -->
    <div class="flex flex-col gap-6 sm:hidden">
      <span class="text-heading-3 text-n-slate-12">
        {{ $t('PROFILE_SETTINGS.FORM.EMAIL_NOTIFICATIONS_SECTION.TITLE') }}
      </span>
      <div class="flex flex-col gap-4">
        <div
          v-for="(notification, index) in filteredNotificationTypes"
          :key="index"
          class="flex flex-row items-start gap-2"
        >
          <CheckBox
            :id="`email_${notification.value}`"
            :value="`email_${notification.value}`"
            :is-checked="checkFlagStatus('email', notification.value)"
            @update="handleEmailInput"
          />
          <span class="text-body-main text-n-slate-12">{{
            $t(notification.label)
          }}</span>
        </div>
      </div>

      <div class="flex items-center justify-start gap-2">
        <span class="text-heading-3 text-n-slate-12">
          {{ $t('PROFILE_SETTINGS.FORM.PUSH_NOTIFICATIONS_SECTION.TITLE') }}
        </span>
      </div>

      <div class="flex flex-col gap-4">
        <div
          v-for="(notification, index) in filteredNotificationTypes"
          :key="index"
          class="flex flex-row items-start gap-2"
        >
          <CheckBox
            :id="`push_${notification.value}`"
            :value="`push_${notification.value}`"
            :is-checked="checkFlagStatus('push', notification.value)"
            @update="handlePushInput"
          />
          <span class="text-body-main text-n-slate-12">{{
            $t(notification.label)
          }}</span>
        </div>
      </div>

      <!-- FORK: popup visual alerts -->
      <p class="text-body-main text-n-slate-11">
        {{ $t('PROFILE_SETTINGS.FORM.NOTIFICATIONS.POPUP_VOICE_NOTE') }}
      </p>
      <div class="flex items-center justify-start gap-2">
        <span class="text-heading-3 text-n-slate-12">
          {{ $t('PROFILE_SETTINGS.FORM.POPUP_NOTIFICATIONS_SECTION.TITLE') }}
        </span>
      </div>

      <div class="flex flex-col gap-4">
        <div
          v-for="(notification, index) in popupNotificationTypes"
          :key="index"
          class="flex flex-row items-start gap-2"
        >
          <CheckBox
            :id="`popup_${notification.value}`"
            :value="`popup_${notification.value}`"
            :is-checked="checkFlagStatus('popup', notification.value)"
            @update="handlePopupInput"
          />
          <span class="text-body-main text-n-slate-12">{{
            $t(notification.label)
          }}</span>
        </div>
      </div>
    </div>

    <div
      class="flex items-center justify-between w-full gap-2 p-4 border border-solid border-n-weak rounded-xl"
    >
      <div class="flex flex-row items-center gap-2">
        <fluent-icon
          icon="alert"
          class="flex-shrink-0 text-n-slate-12"
          size="18"
        />
        <div class="flex flex-col gap-1">
          <span class="text-body-main text-n-slate-12">
            {{ $t('PROFILE_SETTINGS.FORM.NOTIFICATIONS.BROWSER_PERMISSION') }}
          </span>
          <span class="text-body-small text-n-slate-11">
            {{ pushStatusMessage }}
          </span>
        </div>
      </div>
      <ToggleSwitch
        v-model="hasEnabledPushPermissions"
        :disabled="isPushToggleDisabled"
        @change="onRequestPermissions"
      />
    </div>
  </div>
</template>
