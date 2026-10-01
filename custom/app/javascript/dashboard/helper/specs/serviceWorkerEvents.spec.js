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
      location: { origin: 'https://chat.example.test' },
      registration: { showNotification: vi.fn().mockResolvedValue() },
      addEventListener: vi.fn((name, handler) => {
        listeners[name] = handler;
      }),
    };
    vi.stubGlobal('clients', clientsApi);
    vi.stubGlobal('self', workerGlobal);

    await import('../../../../../../public/sw.js');
  });

  it('ignores an invalid push payload', () => {
    const event = {
      data: {
        json: () => {
          throw new SyntaxError('invalid JSON');
        },
      },
      waitUntil: vi.fn(),
    };

    listeners.push(event);

    expect(event.waitUntil).not.toHaveBeenCalled();
    expect(workerGlobal.registration.showNotification).not.toHaveBeenCalled();
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
});
