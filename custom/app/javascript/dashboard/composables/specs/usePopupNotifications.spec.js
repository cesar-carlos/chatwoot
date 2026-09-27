import { beforeEach, describe, expect, it, vi } from 'vitest';

const routerPush = vi.fn();

vi.mock('dashboard/helper/URLHelper', () => ({
  frontendURL: path => `/app/${path}`,
  conversationUrl: ({ accountId, id }) =>
    `accounts/${accountId}/conversations/${id}`,
}));

vi.mock('dashboard/routes', () => ({
  router: { push: (...args) => routerPush(...args) },
}));

import {
  closePopupNotification,
  isViewingConversation,
  popupFlagsForSettings,
  popupMessageBody,
  showPopupNotification,
  withPopupFlagsForAccount,
} from '../usePopupNotifications';

const storeFor = (flagsByAccount, accountId = 1) => ({
  getters: {
    getCurrentAccountId: accountId,
    getUISettings: {
      popup_notification_flags_by_account: flagsByAccount,
    },
  },
});

const messageNotification = (overrides = {}) => ({
  notification: {
    id: 9,
    account_id: 1,
    notification_type: 'assigned_conversation_new_message',
    push_message_body: 'Maria: oi',
    primary_actor: {
      id: 42,
      meta: { sender: { name: 'Maria', thumbnail: '/avatar.png' } },
    },
    ...overrides,
  },
});

describe('usePopupNotifications', () => {
  let closeMock;

  beforeEach(() => {
    closeMock = vi.fn();
    routerPush.mockReset();
    global.Notification = vi.fn(function NotificationMock() {
      this.close = closeMock;
      this.onclick = null;
      this.onclose = null;
    });
    global.Notification.permission = 'granted';
    Object.defineProperty(document, 'visibilityState', {
      configurable: true,
      get: () => 'hidden',
    });
    window.history.pushState({}, '', '/app/accounts/1/conversations/7');
  });

  it('strips the sender prefix from the popup body', () => {
    expect(popupMessageBody('Maria: oi', 'Maria')).toBe('oi');
    expect(popupMessageBody('sem prefixo', 'Maria')).toBe('sem prefixo');
  });

  it('reads flags for the active account and keeps other accounts', () => {
    const settings = withPopupFlagsForAccount(
      {
        popup_notification_flags: ['popup_conversation_creation'],
        popup_notification_flags_by_account: {
          2: ['popup_conversation_mention'],
        },
      },
      1,
      ['popup_assigned_conversation_new_message']
    );

    expect(settings.popup_notification_flags).toBeUndefined();
    expect(popupFlagsForSettings(settings, 1)).toEqual([
      'popup_assigned_conversation_new_message',
    ]);
    expect(popupFlagsForSettings(settings, 2)).toEqual([
      'popup_conversation_mention',
    ]);
  });

  it('falls back to the legacy flat list when no per-account map exists', () => {
    expect(
      popupFlagsForSettings(
        { popup_notification_flags: ['popup_conversation_assignment'] },
        1
      )
    ).toEqual(['popup_conversation_assignment']);
  });

  it('does not show a popup when the flag is off', () => {
    showPopupNotification(messageNotification(), storeFor({ 1: [] }));
    expect(global.Notification).not.toHaveBeenCalled();
  });

  it('does not show a popup for incoming voice calls', () => {
    showPopupNotification(
      messageNotification({ notification_type: 'voice_call_incoming' }),
      storeFor({ 1: ['popup_voice_call_incoming'] })
    );
    expect(global.Notification).not.toHaveBeenCalled();
  });

  it('does not show a popup while that conversation is open', () => {
    Object.defineProperty(document, 'visibilityState', {
      configurable: true,
      get: () => 'visible',
    });
    window.history.pushState({}, '', '/app/accounts/1/conversations/42');

    showPopupNotification(
      messageNotification(),
      storeFor({ 1: ['popup_assigned_conversation_new_message'] })
    );

    expect(global.Notification).not.toHaveBeenCalled();
    expect(isViewingConversation(42)).toBe(true);
    expect(isViewingConversation(7)).toBe(false);
  });

  it('shows a popup when the window is visible on another conversation', () => {
    Object.defineProperty(document, 'visibilityState', {
      configurable: true,
      get: () => 'visible',
    });

    showPopupNotification(
      messageNotification(),
      storeFor({ 1: ['popup_assigned_conversation_new_message'] })
    );

    expect(global.Notification).toHaveBeenCalledWith('Maria', {
      tag: 'chatwoot-popup-42',
      body: 'oi',
      icon: '/avatar.png',
    });
  });

  it('ignores flags saved for a different account', () => {
    showPopupNotification(
      messageNotification(),
      storeFor({ 2: ['popup_assigned_conversation_new_message'] })
    );
    expect(global.Notification).not.toHaveBeenCalled();
  });

  it('focuses the window and opens the conversation on click', async () => {
    const focusMock = vi.fn();
    const originalFocus = window.focus;
    window.focus = focusMock;

    showPopupNotification(
      messageNotification(),
      storeFor({ 1: ['popup_assigned_conversation_new_message'] })
    );

    const notification = global.Notification.mock.results[0].value;
    notification.onclick();
    await vi.dynamicImportSettled?.();
    await Promise.resolve();

    expect(focusMock).toHaveBeenCalled();
    expect(closeMock).toHaveBeenCalled();
    expect(routerPush).toHaveBeenCalledWith({
      path: '/app/accounts/1/conversations/42',
    });

    window.focus = originalFocus;
  });

  it('closes the open popup when the conversation is read', () => {
    showPopupNotification(
      messageNotification(),
      storeFor({ 1: ['popup_assigned_conversation_new_message'] })
    );

    closePopupNotification(42);

    expect(closeMock).toHaveBeenCalled();
  });
});
