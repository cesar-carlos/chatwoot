import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

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
  closeReadPopupNotifications,
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

  afterEach(() => {
    vi.unstubAllGlobals();
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
    expect(isViewingConversation(1, 42)).toBe(true);
    expect(isViewingConversation(1, 7)).toBe(false);
  });

  it('shows the same display id when it belongs to another account', () => {
    Object.defineProperty(document, 'visibilityState', {
      configurable: true,
      get: () => 'visible',
    });
    window.history.pushState({}, '', '/app/accounts/2/conversations/42');

    showPopupNotification(
      messageNotification(),
      storeFor({ 1: ['popup_assigned_conversation_new_message'] }, 2)
    );

    expect(global.Notification).toHaveBeenCalled();
    expect(isViewingConversation(1, 42)).toBe(false);
    expect(isViewingConversation(2, 42)).toBe(true);
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
      tag: 'assigned_conversation_new_message_42_9',
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

  it('uses the service worker when the mobile Notification constructor is unavailable', async () => {
    const close = vi.fn();
    const registration = {
      active: { state: 'activated' },
      showNotification: vi.fn().mockResolvedValue(),
      getNotifications: vi.fn().mockResolvedValue([{ close }]),
    };
    const getRegistration = vi.fn().mockResolvedValue(null);
    const register = vi.fn().mockResolvedValue(registration);
    vi.stubGlobal('navigator', {
      ...navigator,
      serviceWorker: {
        getRegistration,
        register,
        ready: Promise.resolve(registration),
      },
    });
    global.Notification.mockImplementation(() => {
      throw new TypeError('Notification constructor is unavailable');
    });
    global.Notification.permission = 'granted';

    await showPopupNotification(
      messageNotification(),
      storeFor({ 1: ['popup_assigned_conversation_new_message'] })
    );

    expect(register).toHaveBeenCalledWith('/sw.js', {
      updateViaCache: 'none',
    });
    expect(registration.showNotification).toHaveBeenCalledWith('Maria', {
      body: 'oi',
      icon: '/avatar.png',
      tag: 'assigned_conversation_new_message_42_9',
      data: {
        url: '/app/accounts/1/conversations/42',
        account_id: 1,
        notification_id: 9,
        user_id: undefined,
        conversation_id: 42,
      },
      actions: [],
    });

    closePopupNotification(1, 9);
    await vi.waitFor(() => expect(close).toHaveBeenCalledOnce());
  });

  it('reports mobile service worker failures to the caller', async () => {
    vi.stubGlobal('navigator', {
      ...navigator,
      serviceWorker: {
        getRegistration: vi.fn().mockResolvedValue(null),
        register: vi.fn().mockRejectedValue(new Error('Registration failed')),
      },
    });
    global.Notification.mockImplementation(() => {
      throw new TypeError('Notification constructor is unavailable');
    });
    global.Notification.permission = 'granted';

    await expect(
      showPopupNotification(
        messageNotification(),
        storeFor({ 1: ['popup_assigned_conversation_new_message'] })
      )
    ).rejects.toThrow('Registration failed');
  });

  it('uses a persistent desktop notice when the platform supports actions', async () => {
    const registration = {
      active: { state: 'activated' },
      showNotification: vi.fn().mockResolvedValue(),
      getNotifications: vi.fn().mockResolvedValue([]),
    };
    vi.stubGlobal('navigator', {
      ...navigator,
      serviceWorker: {
        getRegistration: vi.fn().mockResolvedValue(registration),
      },
    });
    global.Notification.maxActions = 2;
    await showPopupNotification(
      messageNotification({
        user_id: 7,
        action_labels: { open: 'Abrir conversa', read: 'Marcar como lida' },
      }),
      storeFor({ 1: ['popup_assigned_conversation_new_message'] })
    );
    expect(global.Notification).not.toHaveBeenCalled();
    expect(registration.showNotification).toHaveBeenCalledWith(
      'Maria',
      expect.objectContaining({
        actions: [
          { action: 'open_conversation', title: 'Abrir conversa' },
          { action: 'mark_read', title: 'Marcar como lida' },
        ],
        data: expect.objectContaining({ user_id: 7, notification_id: 9 }),
      })
    );
    closePopupNotification(1, 9);
  });

  it('closes a mobile popup when the conversation is read before display completes', async () => {
    let finishDisplay;
    const close = vi.fn();
    const registration = {
      active: { state: 'activated' },
      showNotification: vi.fn(
        () =>
          new Promise(resolve => {
            finishDisplay = resolve;
          })
      ),
      getNotifications: vi.fn().mockResolvedValue([{ close }]),
    };
    vi.stubGlobal('navigator', {
      ...navigator,
      serviceWorker: {
        getRegistration: vi.fn().mockResolvedValue(registration),
      },
    });
    global.Notification.mockImplementation(() => {
      throw new TypeError('Notification constructor is unavailable');
    });
    global.Notification.permission = 'granted';

    const display = showPopupNotification(
      messageNotification(),
      storeFor({ 1: ['popup_assigned_conversation_new_message'] })
    );
    await vi.waitFor(() =>
      expect(registration.showNotification).toHaveBeenCalledOnce()
    );
    closePopupNotification(1, 9);
    finishDisplay();
    await display;

    expect(registration.getNotifications).toHaveBeenCalledWith({
      tag: 'assigned_conversation_new_message_42_9',
    });
    expect(close).toHaveBeenCalled();
  });

  it('closes only the specific notification and preserves a later one in the same conversation', () => {
    showPopupNotification(
      messageNotification(),
      storeFor({ 1: ['popup_assigned_conversation_new_message'] })
    );
    showPopupNotification(
      messageNotification({ id: 10 }),
      storeFor({ 1: ['popup_assigned_conversation_new_message'] })
    );

    closePopupNotification(2, 9);
    expect(closeMock).not.toHaveBeenCalled();
    closePopupNotification(1, 9);

    expect(closeMock).toHaveBeenCalledTimes(1);
    closeReadPopupNotifications({
      account_id: 1,
      through_notification_id: 10,
      conversation_display_id: 42,
    });

    expect(closeMock).toHaveBeenCalledTimes(2);
  });

  it.each([
    '',
    'inbox/3/',
    'team/2/',
    'label/urgent/',
    'custom_view/4/',
    'mentions/',
    'participating/',
    'unattended/',
  ])('recognizes a visible conversation under %s', prefix => {
    Object.defineProperty(document, 'visibilityState', {
      configurable: true,
      value: 'visible',
    });
    window.history.pushState(
      {},
      '',
      `/app/accounts/1/${prefix}conversations/42`
    );
    expect(isViewingConversation(1, 42)).toBe(true);
    expect(isViewingConversation(2, 42)).toBe(false);
  });

  it('uses normalized router parameters instead of custom-view IDs', () => {
    Object.defineProperty(document, 'visibilityState', {
      configurable: true,
      value: 'visible',
    });
    expect(
      isViewingConversation(1, 42, {
        params: { accountId: '1', id: '42', conversationId: '7' },
      })
    ).toBe(false);
    expect(
      isViewingConversation(1, 42, {
        params: { accountId: '1', conversation_id: '42' },
      })
    ).toBe(true);
  });

  it('recognizes the notification inbox conversation route', () => {
    Object.defineProperty(document, 'visibilityState', {
      configurable: true,
      value: 'visible',
    });
    expect(
      isViewingConversation(1, 42, {
        name: 'inbox_view_conversation',
        params: { accountId: '1', type: 'conversation', id: '42' },
      })
    ).toBe(true);
    window.history.pushState(
      {},
      '',
      '/app/accounts/1/inbox-view/conversation/42'
    );
    expect(isViewingConversation(1, 42)).toBe(true);
  });
});
