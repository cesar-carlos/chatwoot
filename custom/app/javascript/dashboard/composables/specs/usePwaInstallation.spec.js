import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const isPwaStandalone = vi.hoisted(() => vi.fn(() => false));

vi.mock('customDashboard/helper/pushHelper', () => ({
  isPwaStandalone,
}));

describe('usePwaInstallation', () => {
  let listeners;

  beforeEach(() => {
    vi.resetModules();
    vi.restoreAllMocks();
    listeners = {};
    isPwaStandalone.mockReturnValue(false);
    vi.spyOn(window, 'addEventListener').mockImplementation((name, handler) => {
      listeners[name] = handler;
    });
    Object.defineProperty(window, 'isSecureContext', {
      configurable: true,
      value: true,
    });
    Object.defineProperty(navigator, 'userAgent', {
      configurable: true,
      value: 'Mozilla/5.0 Chrome',
    });
    Object.defineProperty(navigator, 'platform', {
      configurable: true,
      value: 'Linux',
    });
    Object.defineProperty(navigator, 'maxTouchPoints', {
      configurable: true,
      value: 0,
    });
    document.head.innerHTML =
      '<link rel="manifest" href="/manifest.webmanifest">';
  });

  afterEach(() => vi.unstubAllGlobals());

  it('captures beforeinstallprompt and opens it only from promptInstall', async () => {
    const { usePwaInstallation } = await import(
      'customDashboard/composables/usePwaInstallation'
    );
    const { status, promptInstall } = usePwaInstallation();
    const event = {
      preventDefault: vi.fn(),
      prompt: vi.fn().mockResolvedValue(),
      userChoice: Promise.resolve({ outcome: 'accepted' }),
    };

    expect(status.value).toBe('unavailable');
    listeners.beforeinstallprompt(event);
    expect(event.preventDefault).toHaveBeenCalledOnce();
    expect(event.prompt).not.toHaveBeenCalled();
    expect(status.value).toBe('available');

    await expect(promptInstall()).resolves.toEqual({ outcome: 'accepted' });
    expect(event.prompt).toHaveBeenCalledOnce();
    expect(status.value).toBe('unavailable');
  });

  it('updates the state when the browser confirms installation', async () => {
    const { usePwaInstallation } = await import(
      'customDashboard/composables/usePwaInstallation'
    );
    const { status } = usePwaInstallation();

    listeners.appinstalled();

    expect(status.value).toBe('installed');
  });

  it('shows Home Screen instructions on iOS', async () => {
    Object.defineProperty(navigator, 'userAgent', {
      configurable: true,
      value: 'Mozilla/5.0 (iPhone)',
    });
    const { usePwaInstallation } = await import(
      'customDashboard/composables/usePwaInstallation'
    );

    expect(usePwaInstallation().status.value).toBe('ios_instructions');
  });

  it('reports an already installed standalone app', async () => {
    isPwaStandalone.mockReturnValue(true);
    const { usePwaInstallation } = await import(
      'customDashboard/composables/usePwaInstallation'
    );

    expect(usePwaInstallation().status.value).toBe('installed');
  });

  it('distinguishes an invalid manifest from a browser that has not offered installation', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue({ ok: false }));
    const { usePwaInstallation } = await import(
      'customDashboard/composables/usePwaInstallation'
    );
    const { status, checkInstallability } = usePwaInstallation();

    await checkInstallability();

    expect(status.value).toBe('manifest_error');
  });

  it('reports an inaccessible installation icon', async () => {
    vi.stubGlobal(
      'fetch',
      vi
        .fn()
        .mockResolvedValueOnce({
          ok: true,
          json: async () => ({
            name: 'Se7e',
            start_url: '/',
            display: 'standalone',
            icons: [
              { src: '/icon-192.png', sizes: '192x192', type: 'image/png' },
              { src: '/icon-512.png', sizes: '512x512', type: 'image/png' },
            ],
          }),
        })
        .mockResolvedValue({ ok: false, headers: { get: () => 'image/png' } })
    );
    const { usePwaInstallation } = await import(
      'customDashboard/composables/usePwaInstallation'
    );
    const { status, checkInstallability } = usePwaInstallation();

    await checkInstallability();

    expect(status.value).toBe('icon_error');
  });

  it('keeps the browser-prompt status when manifest and icons are reachable', async () => {
    vi.stubGlobal(
      'fetch',
      vi
        .fn()
        .mockResolvedValueOnce({
          ok: true,
          json: async () => ({
            name: 'Se7e',
            start_url: '/',
            display: 'standalone',
            icons: [
              { src: '/icon-192.png', sizes: '192x192', type: 'image/png' },
              { src: '/icon-512.png', sizes: '512x512', type: 'image/png' },
            ],
          }),
        })
        .mockResolvedValue({ ok: true, headers: { get: () => 'image/png' } })
    );
    const { usePwaInstallation } = await import(
      'customDashboard/composables/usePwaInstallation'
    );
    const { status, checkInstallability } = usePwaInstallation();

    await checkInstallability();

    expect(status.value).toBe('unavailable');
  });
});
