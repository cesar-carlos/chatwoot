import { mount, flushPromises } from '@vue/test-utils';
import { defineComponent, reactive } from 'vue';
import { beforeEach, describe, expect, it, vi } from 'vitest';
const api = vi.hoisted(() => ({ standalone: vi.fn(), cookie: vi.fn() }));
vi.mock('customDashboard/helper/pushHelper', () => ({
  isPwaStandalone: api.standalone,
}));
vi.mock('js-cookie', () => ({ default: { get: api.cookie } }));

describe('mobile installation and shared native prompt', () => {
  let listeners;
  beforeEach(() => {
    vi.resetModules();
    vi.restoreAllMocks();
    localStorage.clear();
    api.standalone.mockReturnValue(false);
    api.cookie.mockReturnValue('authenticated');
    listeners = {};
    vi.spyOn(window, 'matchMedia').mockReturnValue({
      matches: false,
      addEventListener: vi.fn(),
    });
    vi.spyOn(window, 'addEventListener').mockImplementation(
      (name, callback) => {
        listeners[name] = callback;
      }
    );
    Object.defineProperty(navigator, 'userAgent', {
      configurable: true,
      value: 'Chrome Android',
    });
    Object.defineProperty(navigator, 'platform', {
      configurable: true,
      value: 'Linux',
    });
    Object.defineProperty(window, 'isSecureContext', {
      configurable: true,
      value: true,
    });
    document.head.innerHTML =
      '<link rel="manifest" href="/manifest.webmanifest">';
  });

  const event = (choice = Promise.resolve({ outcome: 'dismissed' })) => ({
    preventDefault: vi.fn(),
    prompt: vi.fn().mockResolvedValue(),
    userChoice: choice,
  });
  const installation = () =>
    import('customDashboard/composables/usePwaInstallation');
  const promotion = async (overrides = {}) => {
    const { usePwaInstallation } = await installation();
    const { usePwaInstallPromotion } = await import(
      'customDashboard/composables/usePwaInstallPromotion'
    );
    const context = reactive({
      ready: true,
      accountId: 2,
      user: { id: 7, accounts: [{ id: 2, status: 'active' }] },
      ...overrides,
    });
    const { status } = usePwaInstallation();
    const wrapper = mount(
      defineComponent({
        setup: () => usePwaInstallPromotion(context, status),
        template: '<div />',
      })
    );
    return { wrapper, context };
  };

  it('shows Android instructions without a native event and hides after appinstalled', async () => {
    const { wrapper } = await promotion();
    expect(wrapper.vm.visible).toBe(true);
    listeners.appinstalled();
    await flushPromises();
    expect(wrapper.vm.visible).toBe(false);
    wrapper.unmount();
  });

  it.each(['Chrome Desktop', 'Chrome Android'])(
    'distinguishes desktop from mobile (%s)',
    async userAgent => {
      Object.defineProperty(navigator, 'userAgent', {
        configurable: true,
        value: userAgent,
      });
      const { wrapper } = await promotion();
      expect(wrapper.vm.visible).toBe(userAgent.includes('Android'));
      wrapper.unmount();
    }
  );

  it('isolates dismissal per user without changing the push invitation or opt-out', async () => {
    const { wrapper, context } = await promotion();
    wrapper.vm.dismiss();
    expect(localStorage.getItem('chatwoot:install-promotion:v1:7')).toBe(
      'dismissed'
    );
    expect(localStorage.getItem('chatwoot:push-invitation:v1:7')).toBeNull();
    expect(localStorage.getItem('chatwoot_push_enabled')).toBeNull();
    wrapper.unmount();
    const again = await promotion();
    expect(again.wrapper.vm.visible).toBe(false);
    again.context.user = { id: 8, accounts: [{ id: 2, status: 'active' }] };
    await flushPromises();
    expect(again.wrapper.vm.visible).toBe(true);
    expect(context.user.id).toBe(7);
    again.wrapper.unmount();
  });

  it('requires loaded account/authentication and respects standalone', async () => {
    const { wrapper, context } = await promotion({ ready: false });
    expect(wrapper.vm.visible).toBe(false);
    context.ready = true;
    context.user.accounts = [];
    await flushPromises();
    expect(wrapper.vm.visible).toBe(false);
    context.user.accounts = [{ id: 2, status: 'active' }];
    await flushPromises();
    expect(wrapper.vm.visible).toBe(true);
    wrapper.unmount();
    api.cookie.mockReturnValue(undefined);
    const anonymous = await promotion();
    expect(anonymous.wrapper.vm.visible).toBe(false);
    anonymous.wrapper.unmount();
    api.cookie.mockReturnValue('authenticated');
    vi.resetModules();
    api.standalone.mockReturnValue(true);
    const installed = await promotion();
    expect(installed.wrapper.vm.visible).toBe(false);
    installed.wrapper.unmount();
  });

  it('does not repeatedly promote installation when storage is unavailable', async () => {
    vi.spyOn(Storage.prototype, 'getItem').mockImplementation(() => {
      throw new Error('storage unavailable');
    });
    const { wrapper } = await promotion();
    expect(wrapper.vm.visible).toBe(false);
    wrapper.unmount();
  });

  it('consumes a native prompt once across surfaces and preserves a newer event', async () => {
    const { usePwaInstallation } = await installation();
    const first = usePwaInstallation();
    const second = usePwaInstallation();
    let choose;
    const oldEvent = event(
      new Promise(resolve => {
        choose = resolve;
      })
    );
    listeners.beforeinstallprompt(oldEvent);
    const pending = first.promptInstall();
    expect(first.busy.value).toBe(true);
    const newEvent = event();
    listeners.beforeinstallprompt(newEvent);
    expect(await second.promptInstall()).toEqual({ outcome: 'unavailable' });
    expect(newEvent.prompt).not.toHaveBeenCalled();
    choose({ outcome: 'dismissed' });
    await pending;
    expect(second.status.value).toBe('available');
    await second.promptInstall();
    await first.promptInstall();
    expect(oldEvent.prompt).toHaveBeenCalledOnce();
    expect(newEvent.prompt).toHaveBeenCalledOnce();
  });

  it('consumes failed prompts without holding the shared lock', async () => {
    const { usePwaInstallation } = await installation();
    const device = usePwaInstallation();
    const prompt = event();
    prompt.prompt.mockRejectedValue(new Error('failed'));
    listeners.beforeinstallprompt(prompt);
    await expect(device.promptInstall()).rejects.toThrow('failed');
    expect(device.busy.value).toBe(false);
    expect(await device.promptInstall()).toEqual({ outcome: 'unavailable' });
  });

  it.each(['iPhone', 'Android Instagram', 'Android; wv'])(
    'uses platform/in-app guidance (%s)',
    async userAgent => {
      Object.defineProperty(navigator, 'userAgent', {
        configurable: true,
        value: userAgent,
      });
      const { usePwaInstallation } = await installation();
      expect(usePwaInstallation().status.value).toBe(
        userAgent === 'iPhone' ? 'ios_instructions' : 'embedded_instructions'
      );
    }
  );

  it('does not offer a captured prompt when a manifest error is verified', async () => {
    const { usePwaInstallation } = await installation();
    const device = usePwaInstallation();
    const prompt = event();
    listeners.beforeinstallprompt(prompt);
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue({ ok: false }));
    await device.checkInstallability();
    expect(device.status.value).toBe('manifest_error');
    expect(await device.promptInstall()).toEqual({ outcome: 'unavailable' });
    expect(prompt.prompt).not.toHaveBeenCalled();
    vi.unstubAllGlobals();
  });

  it('shares validation and blocks native installation for missing icons', async () => {
    const { usePwaInstallation } = await installation();
    const first = usePwaInstallation();
    const second = usePwaInstallation();
    const prompt = event();
    listeners.beforeinstallprompt(prompt);
    const fetchManifest = vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({
        name: 'Se7e',
        start_url: '/',
        display: 'standalone',
        icons: [],
      }),
    });
    vi.stubGlobal('fetch', fetchManifest);
    await Promise.all([
      first.checkInstallability(),
      second.checkInstallability(),
    ]);
    expect(fetchManifest).toHaveBeenCalledOnce();
    expect(first.status.value).toBe('icon_error');
    expect(await second.promptInstall()).toEqual({ outcome: 'unavailable' });
    expect(prompt.prompt).not.toHaveBeenCalled();
    vi.unstubAllGlobals();
  });
});
