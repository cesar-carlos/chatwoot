import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

describe('mobile push worker recovery', () => {
  let listener;
  let show;
  let warning;
  beforeEach(async () => {
    vi.resetModules();
    show = vi.fn().mockResolvedValue();
    warning = vi.spyOn(console, 'warn').mockImplementation(() => {});
    vi.stubGlobal('self', {
      Notification: { maxActions: 2 },
      location: { origin: 'https://chat.example.test' },
      registration: { showNotification: show },
      addEventListener: (name, handler) => {
        if (name === 'push') listener = handler;
      },
    });
    await import('customDashboard/helper/notificationWorker');
  });
  afterEach(() => {
    vi.restoreAllMocks();
    vi.unstubAllGlobals();
  });
  const deliver = async (payload, invalidJson = false) => {
    const event = {
      data: {
        json: () => {
          if (invalidJson) throw new SyntaxError('private-message-content');
          return payload;
        },
      },
      waitUntil: vi.fn(),
    };
    listener(event);
    await event.waitUntil.mock.calls[0][0];
  };

  it.each([
    null,
    [],
    {},
    { title: '   ', body: 'private-message-content', url: 'https://evil.test' },
  ])(
    'shows a safe visible fallback for malformed payload %j',
    async payload => {
      await deliver(payload);
      expect(show).toHaveBeenCalledOnce();
      const [title, options] = show.mock.calls[0];
      expect(title).toBe('New notification');
      expect(options.actions).toEqual([]);
      expect(options.data.url).toBe('https://chat.example.test/app');
      expect(options.data.notification_id).toBeUndefined();
      expect(JSON.stringify(options)).not.toContain('private-message-content');
      expect(warning).toHaveBeenCalledWith(
        'Push notification fallback result=invalid_payload'
      );
    }
  );

  it('handles invalid JSON without logging its contents', async () => {
    await deliver(null, true);
    expect(show).toHaveBeenCalledOnce();
    expect(JSON.stringify(warning.mock.calls)).not.toContain(
      'private-message-content'
    );
  });

  it('falls back once when showing the normal notification fails', async () => {
    show.mockRejectedValueOnce(new Error('private-endpoint'));
    await deliver({
      title: 'New message',
      body: 'private-message-content',
      url: '/app/accounts/1/conversations/2',
    });
    expect(show).toHaveBeenCalledTimes(2);
    expect(show.mock.calls[1]).toEqual([
      'New notification',
      {
        body: 'Open the app to view your notifications.',
        data: { url: 'https://chat.example.test/app' },
      },
    ]);
    expect(JSON.stringify(warning.mock.calls)).not.toContain(
      'private-endpoint'
    );
  });

  it('does not loop or claim success when the OS rejects both displays', async () => {
    show.mockRejectedValue(new Error('Notifications unavailable'));
    await expect(deliver({ title: 'New message' })).rejects.toThrow(
      'Notifications unavailable'
    );
    expect(show).toHaveBeenCalledTimes(2);
  });
});
