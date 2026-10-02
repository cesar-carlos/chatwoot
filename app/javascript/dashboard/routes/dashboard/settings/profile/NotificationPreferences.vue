<script>
import { mapGetters } from 'vuex';
import { useAlert } from 'dashboard/composables';
import TableHeaderCell from 'dashboard/components/widgets/TableHeaderCell.vue';
import CheckBox from 'v3/components/Form/CheckBox.vue';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import NextButton from 'dashboard/components-next/button/Button.vue';
import { NOTIFICATION_TYPES } from './constants';
// FORK: independent delivery preferences for unassigned team conversations
import { withTeamNotificationType } from 'customDashboard/helper/teamNotificationPreferences';
// FORK: explain event triggers consistently across desktop and mobile preferences
import NotificationEventDescription from 'customDashboard/components/notifications/NotificationEventDescription.vue';
// FORK: white-label PWA installation and per-device browser push
import PwaDeviceSettings from 'customDashboard/components/pwa/PwaDeviceSettings.vue';
// FORK: loading guards live in the overlay, including stale-account protection
import { loadNotificationPreferences } from 'customDashboard/helper/notificationPreferences';
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
    CheckBox,
    NextButton,
    PwaDeviceSettings,
    NotificationEventDescription, // FORK: event-specific help from the overlay
  },
  data() {
    return {
      selectedEmailFlags: [],
      selectedPushFlags: [],
      selectedPopupFlags: [],
      notificationSettingsUpdating: false,
      popupSettingsUpdating: false,
      // FORK: do not persist incomplete or failed preference loads
      preferencesLoadedAccount: null,
      preferencesLoadError: false,
      preferencesLoadId: 0,
      popupNotificationLabel: 'Pop-up notification',
      enableAudioAlerts: false,
      // FORK: append the team event without changing upstream notification types
      notificationTypes: withTeamNotificationType(NOTIFICATION_TYPES),
      browserNotificationPermission:
        typeof Notification === 'undefined'
          ? 'unsupported'
          : Notification.permission,
    };
  },
  computed: {
    preferencesReady() {
      return this.preferencesLoadedAccount === String(this.accountId);
    },
    ...mapGetters({
      accountId: 'getCurrentAccountId',
      emailFlags: 'userNotificationSettings/getSelectedEmailFlags',
      pushFlags: 'userNotificationSettings/getSelectedPushFlags',
      uiSettings: 'getUISettings',
      isFeatureEnabledonAccount: 'accounts/isFeatureEnabledonAccount',
    }),
    showOpenPanelPermissionAction() {
      return this.browserNotificationPermission === 'default';
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
      this.selectedEmailFlags = value || [];
    },
    pushFlags(value) {
      this.selectedPushFlags = value || [];
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
      this.loadPreferences();
    },
  },
  mounted() {
    this.loadPreferences();
  },
  methods: {
    // FORK: ignore stale responses after an account switch and expose retry
    loadPreferences() {
      return loadNotificationPreferences(this);
    },
    syncPopupFlags() {
      this.selectedPopupFlags = popupFlagsForSettings(
        this.uiSettings,
        this.accountId
      );
    },
    canSelectPopup(notification) {
      return supportsPopupNotificationType(notification.value);
    },
    notificationChannelLabel(type) {
      if (type === 'popup') return this.popupNotificationLabel;
      return this.$t(
        `PROFILE_SETTINGS.FORM.NOTIFICATIONS.${type.toUpperCase()}`
      );
    },
    checkFlagStatus(type, flagType) {
      const selectedFlags = {
        email: this.selectedEmailFlags,
        push: this.selectedPushFlags,
        popup: this.selectedPopupFlags,
      }[type];
      return (selectedFlags || []).includes(`${type}_${flagType}`);
    },
    async updateNotificationSettings(previousEmailFlags, previousPushFlags) {
      const accountId = this.accountId;
      try {
        await this.$store.dispatch('userNotificationSettings/update', {
          selectedEmailFlags: this.selectedEmailFlags,
          selectedPushFlags: this.selectedPushFlags,
          accountId,
        });
        useAlert(this.$t('PROFILE_SETTINGS.FORM.API.UPDATE_SUCCESS'));
      } catch (error) {
        if (String(accountId) === String(this.accountId)) {
          this.selectedEmailFlags = previousEmailFlags;
          this.selectedPushFlags = previousPushFlags;
        }
        useAlert(this.$t('PROFILE_SETTINGS.FORM.API.UPDATE_ERROR'));
      } finally {
        this.notificationSettingsUpdating = false;
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
      if (!this.preferencesReady || this.notificationSettingsUpdating) return;
      this.notificationSettingsUpdating = true;
      const previousEmailFlags = [...this.selectedEmailFlags];
      const previousPushFlags = [...this.selectedPushFlags];
      this.selectedEmailFlags = this.toggleInput(this.selectedEmailFlags, id);
      await this.updateNotificationSettings(
        previousEmailFlags,
        previousPushFlags
      );
    },
    async handlePushInput(id) {
      if (!this.preferencesReady || this.notificationSettingsUpdating) return;
      this.notificationSettingsUpdating = true;
      const previousEmailFlags = [...this.selectedEmailFlags];
      const previousPushFlags = [...this.selectedPushFlags];
      this.selectedPushFlags = this.toggleInput(this.selectedPushFlags, id);
      await this.updateNotificationSettings(
        previousEmailFlags,
        previousPushFlags
      );
    },
    async requestOpenPanelPermission() {
      try {
        const permission = await requestPopupNotificationPermission();
        this.browserNotificationPermission = permission;
        if (permission !== 'granted') {
          useAlert(
            this.$t(
              'PROFILE_SETTINGS.FORM.NOTIFICATIONS.POPUP_PERMISSION_ERROR'
            )
          );
        }
        return permission;
      } catch (error) {
        this.browserNotificationPermission = 'error';
        useAlert(
          this.$t('PROFILE_SETTINGS.FORM.NOTIFICATIONS.POPUP_PERMISSION_ERROR')
        );
        return 'error';
      }
    },
    async enableOpenPanelNotifications() {
      const permission = await this.requestOpenPanelPermission();
      if (permission === 'granted') {
        useAlert(
          this.$t(
            'PROFILE_SETTINGS.FORM.NOTIFICATIONS.OPEN_PANEL_PERMISSION_SUCCESS'
          )
        );
      }
    },
    // FORK: persist popup flags in ui_settings and request Notification permission
    async handlePopupInput(id) {
      if (!this.preferencesReady || this.popupSettingsUpdating) return;
      const accountId = this.accountId;
      this.popupSettingsUpdating = true;
      try {
        const isEnabling = !this.selectedPopupFlags.includes(id);
        if (isEnabling) {
          const permission = await this.requestOpenPanelPermission();
          if (permission !== 'granted') return;
        }
        if (String(accountId) !== String(this.accountId)) return;
        const previousPopupFlags = [...this.selectedPopupFlags];
        this.selectedPopupFlags = this.toggleInput(this.selectedPopupFlags, id);
        try {
          await this.$store.dispatch('updateUISettingsStrict', {
            uiSettings: withPopupFlagsForAccount(
              this.uiSettings,
              accountId,
              this.selectedPopupFlags
            ),
          });
          useAlert(this.$t('PROFILE_SETTINGS.FORM.API.UPDATE_SUCCESS'));
        } catch (error) {
          if (String(accountId) === String(this.accountId))
            this.selectedPopupFlags = previousPopupFlags;
          useAlert(this.$t('PROFILE_SETTINGS.FORM.API.UPDATE_ERROR'));
        }
      } finally {
        this.popupSettingsUpdating = false;
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
    <!-- FORK: device readiness and event selection remain separate per account -->
    <PwaDeviceSettings
      :push-preferences-ready="
        preferencesReady && !notificationSettingsUpdating
      "
      :selected-push-flags="selectedPushFlags"
      @permission-change="browserNotificationPermission = $event"
    />
    <!-- FORK: a failed load must never look like empty saved preferences -->
    <div
      v-if="!preferencesReady"
      role="status"
      class="flex items-center gap-3 text-sm text-n-slate-11"
    >
      {{
        $t(
          `PROFILE_SETTINGS.FORM.NOTIFICATIONS.${preferencesLoadError ? 'PREFERENCES_LOAD_ERROR' : 'PREFERENCES_LOADING'}`
        )
      }}
      <NextButton
        v-if="preferencesLoadError"
        sm
        :label="$t('PROFILE_SETTINGS.FORM.NOTIFICATIONS.RETRY')"
        @click="loadPreferences"
      />
    </div>
    <!-- FORK: keyboard-accessible destination for the device's event-selection link -->
    <p
      id="profile-settings-notification-events"
      tabindex="-1"
      class="rounded-lg border border-n-slate-6 bg-n-solid-2 px-4 py-3 text-sm text-n-slate-11"
    >
      {{ $t('PROFILE_SETTINGS.FORM.NOTIFICATIONS.DELIVERY_MODES_HINT') }}
    </p>
    <div
      v-if="showOpenPanelPermissionAction"
      class="flex flex-col items-start gap-3 rounded-lg border border-n-slate-6 bg-n-solid-2 px-4 py-3 sm:flex-row sm:items-center sm:justify-between"
    >
      <span class="text-sm text-n-slate-11">
        {{
          $t('PROFILE_SETTINGS.FORM.NOTIFICATIONS.OPEN_PANEL_PERMISSION_HINT')
        }}
      </span>
      <NextButton
        type="button"
        faded
        sm
        :label="
          $t('PROFILE_SETTINGS.FORM.NOTIFICATIONS.OPEN_PANEL_PERMISSION_ACTION')
        "
        @click="enableOpenPanelNotifications"
      />
    </div>
    <!-- Layout for desktop devices -->
    <div class="hidden overflow-x-auto sm:block">
      <div
        class="grid min-h-16 min-w-[42rem] grid-cols-12 items-center gap-4 rounded-t-xl"
      >
        <TableHeaderCell
          :span="6"
          :label="$t('PROFILE_SETTINGS.FORM.NOTIFICATIONS.TYPE_TITLE')"
        >
          <span class="text-heading-3 normal-case text-n-slate-12">
            {{ $t('PROFILE_SETTINGS.FORM.NOTIFICATIONS.TYPE_TITLE') }}
          </span>
        </TableHeaderCell>
        <TableHeaderCell
          :span="2"
          :label="$t('PROFILE_SETTINGS.FORM.NOTIFICATIONS.EMAIL')"
          class="min-w-0 justify-center text-center"
        >
          <span class="text-heading-3 normal-case text-center text-n-slate-12">
            {{ $t('PROFILE_SETTINGS.FORM.NOTIFICATIONS.EMAIL') }}
          </span>
        </TableHeaderCell>
        <TableHeaderCell
          :span="2"
          :label="$t('PROFILE_SETTINGS.FORM.NOTIFICATIONS.PUSH')"
          class="min-w-0 justify-center text-center"
        >
          <span
            class="text-heading-3 break-words text-center normal-case leading-5 text-n-slate-12"
          >
            {{ $t('PROFILE_SETTINGS.FORM.NOTIFICATIONS.PUSH') }}
          </span>
        </TableHeaderCell>
        <!-- FORK: popup visual alerts column -->
        <TableHeaderCell
          :span="2"
          :label="popupNotificationLabel"
          class="min-w-0 justify-center text-center"
        >
          <span
            class="text-heading-3 break-words text-center normal-case leading-5 text-n-slate-12"
          >
            {{ popupNotificationLabel }}
          </span>
        </TableHeaderCell>
      </div>
      <div
        v-for="(notification, index) in filteredNotificationTypes"
        :key="index"
      >
        <div
          class="grid min-h-12 min-w-[42rem] grid-cols-12 items-center gap-4 rounded-t-xl py-2"
        >
          <div
            class="flex flex-row items-start gap-2 col-span-6 px-0 py-2 text-sm tracking-[0.5] rtl:text-right"
          >
            <span class="text-body-main text-n-slate-12">
              {{ $t(notification.label) }}
              <!-- FORK: team assignment is not a per-message notification -->
              <NotificationEventDescription
                :description="notification.description"
              />
            </span>
          </div>
          <div
            v-for="type in ['email', 'push', 'popup']"
            :key="type"
            class="flex items-center justify-center col-span-2 min-w-0 px-0 text-sm"
          >
            <CheckBox
              v-if="type !== 'popup' || canSelectPopup(notification)"
              :value="`${type}_${notification.value}`"
              :is-checked="checkFlagStatus(type, notification.value)"
              :disabled="
                type === 'popup'
                  ? !preferencesReady || popupSettingsUpdating
                  : !preferencesReady || notificationSettingsUpdating
              "
              class="disabled:cursor-wait disabled:opacity-50"
              :aria-label="`${$t(notification.label)} — ${notificationChannelLabel(type)}`"
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
            :disabled="!preferencesReady || notificationSettingsUpdating"
            class="disabled:cursor-wait disabled:opacity-50"
            @update="handleEmailInput"
          />
          <label
            :for="`email_${notification.value}`"
            class="text-body-main text-n-slate-12"
          >
            <span>{{ $t(notification.label) }}</span>
            <!-- FORK: shared event explanation on mobile -->
            <NotificationEventDescription
              :description="notification.description"
            />
          </label>
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
            :disabled="!preferencesReady || notificationSettingsUpdating"
            class="disabled:cursor-wait disabled:opacity-50"
            @update="handlePushInput"
          />
          <label
            :for="`push_${notification.value}`"
            class="text-body-main text-n-slate-12"
          >
            <span>{{ $t(notification.label) }}</span>
            <!-- FORK: shared event explanation on mobile -->
            <NotificationEventDescription
              :description="notification.description"
            />
          </label>
        </div>
      </div>

      <!-- FORK: popup visual alerts -->
      <p class="text-body-main text-n-slate-11">
        {{ $t('PROFILE_SETTINGS.FORM.NOTIFICATIONS.POPUP_VOICE_NOTE') }}
      </p>
      <div class="flex items-center justify-start gap-2">
        <span class="text-heading-3 text-n-slate-12">
          {{ popupNotificationLabel }}
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
            :disabled="!preferencesReady || popupSettingsUpdating"
            class="disabled:cursor-wait disabled:opacity-50"
            @update="handlePopupInput"
          />
          <label
            :for="`popup_${notification.value}`"
            class="text-body-main text-n-slate-12"
          >
            <span>{{ $t(notification.label) }}</span>
            <!-- FORK: shared event explanation on mobile -->
            <NotificationEventDescription
              :description="notification.description"
            />
          </label>
        </div>
      </div>
    </div>
  </div>
</template>
