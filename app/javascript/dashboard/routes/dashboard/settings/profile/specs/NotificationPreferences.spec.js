import { beforeEach, describe, expect, it, vi } from 'vitest';

const {
  ensurePushSubscription,
  requestAndSubscribe,
  requestPopupNotificationPermission,
  unsubscribePush,
  useAlert,
} = vi.hoisted(() => ({
  ensurePushSubscription: vi.fn(),
  requestAndSubscribe: vi.fn(),
  requestPopupNotificationPermission: vi.fn(),
  unsubscribePush: vi.fn(),
  useAlert: vi.fn(),
}));

vi.mock('dashboard/composables', () => ({ useAlert }));
vi.mock('dashboard/helper/pushHelper.js', () => ({
  ensurePushSubscription,
  getPushEnvironment: () => ({ status: 'default' }),
  requestAndSubscribe,
  unsubscribePush,
}));
vi.mock('customDashboard/composables/usePopupNotifications', () => ({
  popupFlagsForSettings: vi.fn(() => []),
  requestPopupNotificationPermission,
  supportsPopupNotificationType: vi.fn(() => true),
  withPopupFlagsForAccount: vi.fn((settings, accountId, flags) => ({
    ...settings,
    popup_notification_flags_by_account: { [accountId]: flags },
  })),
}));
vi.mock('shared/composables/useBranding', () => ({
  useBranding: () => ({ replaceInstallationName: value => value }),
}));

import NotificationPreferences from '../NotificationPreferences.vue';

const { methods } = NotificationPreferences;
const translate = key => key;

describe('NotificationPreferences', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('subscribes when the switch model was changed to enabled', async () => {
    requestAndSubscribe.mockResolvedValue({
      status: 'subscribed',
      permission: 'granted',
    });
    const context = {
      hasEnabledPushPermissions: true,
      pushStatus: 'unsubscribed',
      browserNotificationPermission: 'default',
      $t: translate,
    };

    await methods.onRequestPermissions.call(context);

    expect(requestAndSubscribe).toHaveBeenCalledOnce();
    expect(unsubscribePush).not.toHaveBeenCalled();
    expect(context.hasEnabledPushPermissions).toBe(true);
    expect(context.browserNotificationPermission).toBe('granted');
  });

  it('unsubscribes when the switch model was changed to disabled', async () => {
    unsubscribePush.mockResolvedValue({
      status: 'unsubscribed',
      permission: 'granted',
    });
    const context = {
      hasEnabledPushPermissions: false,
      pushStatus: 'subscribed',
      browserNotificationPermission: 'granted',
      $t: translate,
    };

    await methods.onRequestPermissions.call(context);

    expect(unsubscribePush).toHaveBeenCalledOnce();
    expect(requestAndSubscribe).not.toHaveBeenCalled();
    expect(context.hasEnabledPushPermissions).toBe(false);
  });

  it('rolls popup preferences back when strict persistence fails', async () => {
    const selectedPopupFlags = ['popup_assigned_conversation_new_message'];
    const dispatch = vi.fn().mockRejectedValue(new Error('request failed'));
    const context = {
      accountId: 1,
      selectedPopupFlags: [...selectedPopupFlags],
      uiSettings: {},
      $store: { dispatch },
      $t: translate,
      toggleInput: methods.toggleInput,
    };

    await methods.handlePopupInput.call(
      context,
      'popup_assigned_conversation_new_message'
    );

    expect(dispatch).toHaveBeenCalledWith(
      'updateUISettingsStrict',
      expect.any(Object)
    );
    expect(context.selectedPopupFlags).toEqual(selectedPopupFlags);
    expect(useAlert).toHaveBeenCalledWith(
      'PROFILE_SETTINGS.FORM.API.UPDATE_ERROR'
    );
  });
});
