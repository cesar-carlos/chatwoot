import { describe, expect, it } from 'vitest';
import { NOTIFICATION_TYPES } from 'dashboard/routes/dashboard/settings/profile/constants';
import { NOTIFICATION_TYPES_MAPPING } from 'dashboard/routes/dashboard/inbox/helpers/InboxViewHelpers';
import NotificationPreferences from 'dashboard/routes/dashboard/settings/profile/NotificationPreferences.vue';
import {
  supportsPopupNotificationType,
  isPopupNotificationEnabled,
} from 'customDashboard/composables/usePopupNotifications';
import {
  TEAM_ASSIGNMENT_TYPE,
  withTeamNotificationType,
} from 'customDashboard/helper/teamNotificationPreferences';

describe('team assignment notification preferences', () => {
  it('adds an independent row after individual assignment without mutating upstream types', () => {
    const types = withTeamNotificationType(NOTIFICATION_TYPES);
    expect(types[2]).toEqual({
      value: TEAM_ASSIGNMENT_TYPE,
      label:
        'PROFILE_SETTINGS.FORM.NOTIFICATIONS.TYPES.TEAM_CONVERSATION_ASSIGNMENT',
    });
    expect(NOTIFICATION_TYPES).not.toContainEqual(types[2]);
    expect(NotificationPreferences.data().notificationTypes).toEqual(types);
    expect(NOTIFICATION_TYPES_MAPPING.TEAM_CONVERSATION_ASSIGNMENT).toEqual([
      'i-lucide-users',
      'text-n-blue-11',
    ]);
  });

  it('keeps independent channel selections and supports the popup event per account', () => {
    const context = {
      selectedEmailFlags: [`email_${TEAM_ASSIGNMENT_TYPE}`],
      selectedPushFlags: [],
      selectedPopupFlags: [`popup_${TEAM_ASSIGNMENT_TYPE}`],
    };
    const check = NotificationPreferences.methods.checkFlagStatus.bind(context);
    expect(check('email', TEAM_ASSIGNMENT_TYPE)).toBe(true);
    expect(check('push', TEAM_ASSIGNMENT_TYPE)).toBe(false);
    expect(check('popup', TEAM_ASSIGNMENT_TYPE)).toBe(true);
    expect(supportsPopupNotificationType(TEAM_ASSIGNMENT_TYPE)).toBe(true);
    const store = {
      getters: {
        getUISettings: {
          popup_notification_flags_by_account: {
            1: [`popup_${TEAM_ASSIGNMENT_TYPE}`],
          },
        },
      },
    };
    expect(isPopupNotificationEnabled(TEAM_ASSIGNMENT_TYPE, store, 1)).toBe(
      true
    );
    expect(isPopupNotificationEnabled(TEAM_ASSIGNMENT_TYPE, store, 2)).toBe(
      false
    );
  });
});
