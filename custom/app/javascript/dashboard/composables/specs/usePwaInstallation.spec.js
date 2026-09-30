import { beforeEach, describe, expect, it, vi } from 'vitest';

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
});
