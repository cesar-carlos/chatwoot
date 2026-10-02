import { beforeEach, describe, expect, it, vi } from 'vitest';

describe('PWA service worker', () => {
  let listeners;
  let clientsApi;
  let workerGlobal;

  beforeEach(async () => {
    vi.resetModules();
    vi.unstubAllGlobals();
    listeners = {};
    clientsApi = {
      matchAll: vi.fn().mockResolvedValue([]),
      openWindow: vi.fn().mockResolvedValue(),
    };
    workerGlobal = {
      Notification: { maxActions: 2 },
      crypto: { randomUUID: () => 'test-nonce' },
      location: { origin: 'https://chat.example.test' },
      registration: { showNotification: vi.fn().mockResolvedValue() },
      addEventListener: vi.fn((name, handler) => {
        listeners[name] = handler;
      }),
    };
    vi.stubGlobal('clients', clientsApi);
    vi.stubGlobal('self', workerGlobal);

    await import('../notificationWorker.js');
  });

  it('shows a content-free fallback for an invalid push payload', async () => {
    const event = {
      data: {
        json: () => {
          throw new SyntaxError('invalid JSON');
        },
      },
      waitUntil: vi.fn(),
    };

    listeners.push(event);

    await event.waitUntil.mock.calls[0][0];
    expect(workerGlobal.registration.showNotification).toHaveBeenCalledWith(
      'New notification',
      expect.objectContaining({
        body: 'Open the app to view your notifications.',
        actions: [],
        data: expect.objectContaining({ url: 'https://chat.example.test/app' }),
      })
    );
  });

  it('shows all notification fields from a valid payload', async () => {
    const event = {
      data: {
        json: () => ({
          title: 'New message',
          body: 'Hello',
          icon: '/icon.png',
          tag: 'conversation-1',
          url: '/app/accounts/1/conversations/1',
        }),
      },
      waitUntil: vi.fn(),
    };

    listeners.push(event);
    await event.waitUntil.mock.calls[0][0];

    expect(workerGlobal.registration.showNotification).toHaveBeenCalledWith(
      'New message',
      expect.objectContaining({
        body: 'Hello',
        icon: '/icon.png',
        tag: 'conversation-1',
      })
    );
  });

  it('focuses and navigates an existing same-origin client', async () => {
    const client = {
      url: 'https://chat.example.test/app',
      navigate: vi.fn().mockResolvedValue(),
      focus: vi.fn().mockResolvedValue(),
    };
    client.navigate.mockResolvedValue(client);
    client.focus.mockResolvedValue(client);
    clientsApi.matchAll.mockResolvedValue([client]);
    const notification = {
      data: { url: '/app/accounts/1/conversations/22' },
      close: vi.fn(),
    };
    const event = { notification, waitUntil: vi.fn() };

    listeners.notificationclick(event);
    await event.waitUntil.mock.calls[0][0];

    expect(notification.close).toHaveBeenCalledOnce();
    expect(client.navigate).toHaveBeenCalledWith(
      'https://chat.example.test/app/accounts/1/conversations/22'
    );
    expect(client.focus).toHaveBeenCalledOnce();
    expect(clientsApi.openWindow).not.toHaveBeenCalled();
  });

  it('prefers the dashboard window for the notification account', async () => {
    const otherAccountClient = {
      url: 'https://chat.example.test/app/accounts/1/conversations/11',
      navigate: vi.fn().mockResolvedValue(),
      focus: vi.fn().mockResolvedValue(),
    };
    const targetAccountClient = {
      url: 'https://chat.example.test/app/accounts/2/conversations/12',
      navigate: vi.fn().mockResolvedValue(),
      focus: vi.fn().mockResolvedValue(),
    };
    targetAccountClient.navigate.mockResolvedValue(targetAccountClient);
    targetAccountClient.focus.mockResolvedValue(targetAccountClient);
    clientsApi.matchAll.mockResolvedValue([
      otherAccountClient,
      targetAccountClient,
    ]);
    const event = {
      notification: {
        data: { url: '/app/accounts/2/conversations/22' },
        close: vi.fn(),
      },
      waitUntil: vi.fn(),
    };

    listeners.notificationclick(event);
    await event.waitUntil.mock.calls[0][0];

    expect(targetAccountClient.navigate).toHaveBeenCalledWith(
      'https://chat.example.test/app/accounts/2/conversations/22'
    );
    expect(targetAccountClient.focus).toHaveBeenCalledOnce();
    expect(otherAccountClient.navigate).not.toHaveBeenCalled();
  });

  it('opens a new window instead of replacing another account when several are open', async () => {
    const clientsForOtherAccounts = [1, 3].map(accountId => ({
      url: `https://chat.example.test/app/accounts/${accountId}/conversations/11`,
      navigate: vi.fn(),
      focus: vi.fn(),
    }));
    clientsApi.matchAll.mockResolvedValue(clientsForOtherAccounts);
    const event = {
      notification: {
        data: { url: '/app/accounts/2/conversations/22' },
        close: vi.fn(),
      },
      waitUntil: vi.fn(),
    };

    listeners.notificationclick(event);
    await event.waitUntil.mock.calls[0][0];

    expect(clientsApi.openWindow).toHaveBeenCalledWith(
      'https://chat.example.test/app/accounts/2/conversations/22'
    );
    clientsForOtherAccounts.forEach(client => {
      expect(client.navigate).not.toHaveBeenCalled();
    });
  });

  it('does not navigate an unrelated same-origin page', async () => {
    const portalClient = {
      url: 'https://chat.example.test/hc/portal',
      navigate: vi.fn(),
      focus: vi.fn(),
    };
    clientsApi.matchAll.mockResolvedValue([portalClient]);
    const notification = {
      data: { url: '/app/accounts/1/conversations/22' },
      close: vi.fn(),
    };
    const event = { notification, waitUntil: vi.fn() };

    listeners.notificationclick(event);
    await event.waitUntil.mock.calls[0][0];

    expect(portalClient.navigate).not.toHaveBeenCalled();
    expect(portalClient.focus).not.toHaveBeenCalled();
    expect(clientsApi.openWindow).toHaveBeenCalledWith(
      'https://chat.example.test/app/accounts/1/conversations/22'
    );
  });

  it('never opens an external notification URL', async () => {
    const notification = {
      data: { url: 'https://malicious.example/phishing' },
      close: vi.fn(),
    };
    const event = { notification, waitUntil: vi.fn() };

    listeners.notificationclick(event);
    await event.waitUntil.mock.calls[0][0];

    expect(clientsApi.openWindow).toHaveBeenCalledWith(
      'https://chat.example.test/'
    );
  });

  it.each(['navigate', 'focus', 'disappeared'])(
    'opens a fresh window after client %s fails',
    async failure => {
      const client = {
        url: 'https://chat.example.test/app/accounts/1',
        navigate: vi.fn(),
        focus: vi.fn(),
      };
      client.navigate.mockResolvedValue(
        failure === 'disappeared' ? null : client
      );
      client.focus.mockResolvedValue(client);
      if (failure !== 'disappeared')
        client[failure].mockRejectedValue(new Error('closed'));
      clientsApi.matchAll.mockResolvedValue([client]);
      const event = {
        notification: {
          data: { url: '/app/accounts/1/conversations/22' },
          close: vi.fn(),
        },
        waitUntil: vi.fn(),
      };
      listeners.notificationclick(event);
      await event.waitUntil.mock.calls[0][0];
      expect(clientsApi.openWindow).toHaveBeenCalledWith(
        'https://chat.example.test/app/accounts/1/conversations/22'
      );
    }
  );

  it('offers actions only on real recipient-bound notifications when supported', async () => {
    const event = {
      data: {
        json: () => ({
          title: 'Message',
          url: '/app/accounts/1/conversations/22',
          user_id: 7,
          account_id: 1,
          notification_id: 9,
        }),
      },
      waitUntil: vi.fn(),
    };
    listeners.push(event);
    await event.waitUntil.mock.calls[0][0];
    expect(
      workerGlobal.registration.showNotification.mock.calls[0][1].actions
    ).toEqual([
      { action: 'open_conversation', title: 'Open conversation' },
      { action: 'mark_read', title: 'Mark as read' },
    ]);
    workerGlobal.Notification.maxActions = 0;
    listeners.push(event);
    expect(
      workerGlobal.registration.showNotification.mock.calls[1][1].actions
    ).toEqual([]);
  });

  it('does not offer actions on diagnostic or legacy payloads', () => {
    listeners.push({
      data: { json: () => ({ title: 'Diagnostic', url: '/app' }) },
      waitUntil: vi.fn(),
    });
    expect(
      workerGlobal.registration.showNotification.mock.calls[0][1].actions
    ).toEqual([]);
  });

  it('opens the notification list for a single read and consumes its intent once', async () => {
    const event = {
      action: 'mark_read',
      notification: {
        data: {
          url: '/app/accounts/1/conversations/22',
          user_id: 7,
          account_id: 1,
          notification_id: 9,
        },
        close: vi.fn(),
      },
      waitUntil: vi.fn(),
    };
    listeners.notificationclick(event);
    await event.waitUntil.mock.calls[0][0];
    expect(clientsApi.openWindow).toHaveBeenCalledWith(
      'https://chat.example.test/app/accounts/1/inbox-view?notification_intent=test-nonce'
    );
    const port = { postMessage: vi.fn() };
    const consume = {
      data: { type: 'consume-notification-intent', nonce: 'test-nonce' },
      source: { url: 'https://chat.example.test/app/accounts/1/inbox-view' },
      ports: [port],
    };
    listeners.message(consume);
    expect(port.postMessage).toHaveBeenCalledWith(
      expect.objectContaining({ user_id: 7, notification_id: 9, account_id: 1 })
    );
    listeners.message(consume);
    expect(port.postMessage).toHaveBeenLastCalledWith(null);
  });

  it('rejects an intent from another account', async () => {
    const event = {
      action: 'mark_read',
      notification: {
        data: {
          url: '/app/accounts/1/conversations/22',
          user_id: 7,
          account_id: 1,
          notification_id: 9,
        },
        close: vi.fn(),
      },
      waitUntil: vi.fn(),
    };
    listeners.notificationclick(event);
    await event.waitUntil.mock.calls[0][0];
    const port = { postMessage: vi.fn() };
    listeners.message({
      data: { type: 'consume-notification-intent', nonce: 'test-nonce' },
      source: { url: 'https://chat.example.test/app/accounts/2' },
      ports: [port],
    });
    expect(port.postMessage).toHaveBeenCalledWith(null);
  });

  it('dismisses a push notice marked read while its display is still pending', async () => {
    let finish;
    workerGlobal.registration.showNotification.mockImplementation(
      () =>
        new Promise(resolve => {
          finish = resolve;
        })
    );
    const data = {
      title: 'Message',
      tag: 'notice-9',
      url: '/app/accounts/1/conversations/22',
      user_id: 7,
      account_id: 1,
      notification_id: 9,
    };
    const close = vi.fn();
    const laterClose = vi.fn();
    workerGlobal.registration.getNotifications = vi.fn().mockResolvedValue([
      { data, close },
      { data: { ...data, notification_id: 10 }, close: laterClose },
    ]);
    const event = { data: { json: () => data }, waitUntil: vi.fn() };
    listeners.push(event);
    listeners.message({
      data: {
        type: 'notifications-read',
        receipt: { account_id: 1, user_id: 7, through_notification_id: 9 },
      },
    });
    finish();
    await event.waitUntil.mock.calls[0][0];
    expect(close).toHaveBeenCalledOnce();
    expect(laterClose).not.toHaveBeenCalled();
  });
});
