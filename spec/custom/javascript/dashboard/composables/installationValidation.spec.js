import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
vi.mock('customDashboard/helper/pushHelper', () => ({
  isPwaStandalone: () => false,
}));

const manifestResponse = () => ({
  ok: true,
  status: 200,
  json: async () => ({
    name: 'Se7e',
    start_url: '/',
    display: 'standalone',
    icons: [
      { src: '/icon-192.png', type: 'image/png', sizes: '192x192' },
      { src: '/icon-512.png', type: 'image/png', sizes: '512x512' },
    ],
  }),
});
const iconResponse = () => ({
  ok: true,
  status: 200,
  headers: { get: () => 'image/png' },
});
const waitUntilAborted = (url, { signal }) =>
  new Promise((resolve, reject) => {
    signal.addEventListener(
      'abort',
      () => reject(new DOMException('Aborted', 'AbortError')),
      { once: true }
    );
  });

describe('bounded installation checks', () => {
  let listeners;
  beforeEach(() => {
    vi.resetModules();
    listeners = {};
    document.head.innerHTML =
      '<link rel="manifest" href="/manifest.webmanifest">';
    Object.defineProperty(window, 'isSecureContext', {
      configurable: true,
      value: true,
    });
    Object.defineProperty(navigator, 'userAgent', {
      configurable: true,
      value: 'Chrome Android',
    });
    vi.spyOn(window, 'matchMedia').mockReturnValue({
      matches: false,
      addEventListener: vi.fn(),
    });
    vi.spyOn(window, 'addEventListener').mockImplementation(
      (name, listener) => {
        listeners[name] = listener;
      }
    );
  });
  afterEach(() => {
    vi.useRealTimers();
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
  });

  it('aborts a stalled manifest and recovers only after an explicit new check', async () => {
    vi.useFakeTimers();
    const fetchResource = vi.fn(waitUntilAborted);
    vi.stubGlobal('fetch', fetchResource);
    const { usePwaInstallation, PWA_VALIDATION_TIMEOUT_MS } = await import(
      'customDashboard/composables/usePwaInstallation'
    );
    const installation = usePwaInstallation();
    const prompt = {
      preventDefault: vi.fn(),
      prompt: vi.fn(),
      userChoice: Promise.resolve({ outcome: 'accepted' }),
    };
    listeners.beforeinstallprompt(prompt);
    const pending = installation.checkInstallability();
    expect(installation.status.value).toBe('checking');
    expect(await installation.promptInstall()).toEqual({
      outcome: 'unavailable',
    });
    await vi.advanceTimersByTimeAsync(PWA_VALIDATION_TIMEOUT_MS);
    await pending;
    expect(installation.status.value).toBe('connection_timeout');
    expect(fetchResource).toHaveBeenCalledOnce();
    expect(fetchResource.mock.calls[0][1].signal.aborted).toBe(true);
    expect(vi.getTimerCount()).toBe(0);
    fetchResource
      .mockResolvedValueOnce(manifestResponse())
      .mockResolvedValue(iconResponse());
    await installation.checkInstallability();
    expect(installation.status.value).toBe('available');
    expect(fetchResource).toHaveBeenCalledTimes(4);
    expect(prompt.prompt).not.toHaveBeenCalled();
  });

  it('uses one timeout for the manifest and both parallel icon requests', async () => {
    vi.useFakeTimers();
    const fetchResource = vi
      .fn(waitUntilAborted)
      .mockResolvedValueOnce(manifestResponse());
    vi.stubGlobal('fetch', fetchResource);
    const { usePwaInstallation, PWA_VALIDATION_TIMEOUT_MS } = await import(
      'customDashboard/composables/usePwaInstallation'
    );
    const installation = usePwaInstallation();
    const pending = installation.checkInstallability();
    await vi.advanceTimersByTimeAsync(0);
    expect(fetchResource).toHaveBeenCalledTimes(3);
    await vi.advanceTimersByTimeAsync(PWA_VALIDATION_TIMEOUT_MS);
    await pending;
    expect(installation.status.value).toBe('connection_timeout');
    const signals = fetchResource.mock.calls.map(call => call[1].signal);
    expect(new Set(signals).size).toBe(1);
    expect(signals.every(signal => signal.aborted)).toBe(true);
    expect(vi.getTimerCount()).toBe(0);
  });

  it('does not classify a connection failure as a broken manifest', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn().mockRejectedValue(new TypeError('Network failed'))
    );
    const { usePwaInstallation } = await import(
      'customDashboard/composables/usePwaInstallation'
    );
    const installation = usePwaInstallation();
    await installation.checkInstallability();
    expect(installation.status.value).toBe('connection_error');
  });

  it.each([
    [404, 'manifest_error'],
    [503, 'connection_error'],
  ])('distinguishes manifest HTTP %s', async (status, expected) => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue({ ok: false, status }));
    const { usePwaInstallation } = await import(
      'customDashboard/composables/usePwaInstallation'
    );
    const installation = usePwaInstallation();
    await installation.checkInstallability();
    expect(installation.status.value).toBe(expected);
  });

  it.each([
    [404, 'icon_error'],
    [503, 'connection_error'],
  ])('distinguishes icon HTTP %s', async (status, expected) => {
    vi.stubGlobal(
      'fetch',
      vi
        .fn()
        .mockResolvedValueOnce(manifestResponse())
        .mockResolvedValue({ ok: false, status })
    );
    const { usePwaInstallation } = await import(
      'customDashboard/composables/usePwaInstallation'
    );
    const installation = usePwaInstallation();
    await installation.checkInstallability();
    expect(installation.status.value).toBe(expected);
  });

  it.each([
    [new SyntaxError('Invalid JSON'), 'manifest_error'],
    [new TypeError('Body connection lost'), 'connection_error'],
  ])(
    'distinguishes parsing from transport failure (%s)',
    async (error, expected) => {
      vi.stubGlobal(
        'fetch',
        vi.fn().mockResolvedValue({
          ok: true,
          json: vi.fn().mockRejectedValue(error),
        })
      );
      const { usePwaInstallation } = await import(
        'customDashboard/composables/usePwaInstallation'
      );
      const installation = usePwaInstallation();
      await installation.checkInstallability();
      expect(installation.status.value).toBe(expected);
    }
  );
});
