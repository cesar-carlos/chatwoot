import { beforeEach, describe, expect, it, vi } from 'vitest';

const { requestPopupNotificationPermission, useAlert } = vi.hoisted(() => ({
  requestPopupNotificationPermission: vi.fn(),
  useAlert: vi.fn(),
}));

vi.mock('dashboard/composables', () => ({ useAlert }));
vi.mock('customDashboard/composables/usePopupNotifications', () => ({
  popupFlagsForSettings: vi.fn(() => []),
  requestPopupNotificationPermission,
  supportsPopupNotificationType: vi.fn(() => true),
  withPopupFlagsForAccount: vi.fn((settings, accountId, flags) => ({
    ...settings,
    popup_notification_flags_by_account: { [accountId]: flags },
  })),
}));
vi.mock('customDashboard/components/pwa/PwaDeviceSettings.vue', () => ({
  default: { template: '<div />' },
}));

import NotificationPreferences from 'dashboard/routes/dashboard/settings/profile/NotificationPreferences.vue';

const { methods } = NotificationPreferences;

describe('custom notification preferences', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('blocks saving preferences before loading succeeds', async () => {
    const context = { preferencesReady: false, $store: { dispatch: vi.fn() } };
    await methods.handleEmailInput.call(
      context,
      'email_conversation_assignment'
    );
    await methods.handlePushInput.call(context, 'push_conversation_assignment');
    await methods.handlePopupInput.call(
      context,
      'popup_conversation_assignment'
    );
    expect(context.$store.dispatch).not.toHaveBeenCalled();
  });

  it('keeps failed preference loads unavailable and allows a retry', async () => {
    const dispatch = vi
      .fn()
      .mockRejectedValueOnce(new Error('offline'))
      .mockResolvedValueOnce({});
    const context = {
      accountId: 1,
      preferencesLoadId: 0,
      $store: { dispatch },
    };
    await methods.loadPreferences.call(context);
    expect(context.preferencesLoadError).toBe(true);
    expect(context.preferencesLoadedAccount).toBeNull();
    await methods.loadPreferences.call(context);
    expect(context.preferencesLoadedAccount).toBe('1');
    expect(context.preferencesLoadError).toBe(false);
  });

  it('rolls popup preferences back when strict persistence fails', async () => {
    const selectedPopupFlags = ['popup_assigned_conversation_new_message'];
    const dispatch = vi.fn().mockRejectedValue(new Error('request failed'));
    const context = {
      preferencesReady: true,
      accountId: 1,
      selectedPopupFlags: [...selectedPopupFlags],
      uiSettings: {},
      $store: { dispatch },
      $t: key => key,
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

  it('blocks concurrent popup preference updates', async () => {
    let completeRequest;
    const dispatch = vi.fn(
      () =>
        new Promise(resolve => {
          completeRequest = resolve;
        })
    );
    requestPopupNotificationPermission.mockResolvedValue('granted');
    const context = {
      preferencesReady: true,
      accountId: 1,
      selectedPopupFlags: [],
      popupSettingsUpdating: false,
      uiSettings: {},
      $store: { dispatch },
      $t: key => key,
      toggleInput: methods.toggleInput,
      requestOpenPanelPermission: methods.requestOpenPanelPermission,
    };

    const firstUpdate = methods.handlePopupInput.call(
      context,
      'popup_conversation_assignment'
    );
    await vi.waitFor(() => expect(dispatch).toHaveBeenCalledOnce());
    await methods.handlePopupInput.call(
      context,
      'popup_assigned_conversation_new_message'
    );

    expect(dispatch).toHaveBeenCalledOnce();
    expect(context.selectedPopupFlags).toEqual([
      'popup_conversation_assignment',
    ]);
    completeRequest();
    await firstUpdate;
    expect(context.popupSettingsUpdating).toBe(false);
  });

  it('blocks concurrent email and push preference updates', async () => {
    let completeRequest;
    const dispatch = vi.fn(
      () =>
        new Promise(resolve => {
          completeRequest = resolve;
        })
    );
    const context = {
      preferencesReady: true,
      selectedEmailFlags: [],
      selectedPushFlags: [],
      notificationSettingsUpdating: false,
      $store: { dispatch },
      $t: key => key,
      toggleInput: methods.toggleInput,
      updateNotificationSettings: methods.updateNotificationSettings,
    };

    const firstUpdate = methods.handleEmailInput.call(
      context,
      'email_conversation_assignment'
    );
    await methods.handlePushInput.call(
      context,
      'push_assigned_conversation_new_message'
    );

    expect(dispatch).toHaveBeenCalledOnce();
    expect(context.selectedPushFlags).toEqual([]);
    completeRequest();
    await firstUpdate;
    expect(context.notificationSettingsUpdating).toBe(false);
  });
});
