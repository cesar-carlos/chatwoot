import { mount, flushPromises } from '@vue/test-utils';
import { ref } from 'vue';
import { beforeEach, describe, expect, it, vi } from 'vitest';
const api = vi.hoisted(() => ({
  platform: vi.fn(),
  embedded: vi.fn(),
  cookie: vi.fn(),
  install: vi.fn(),
  alert: vi.fn(),
  checkInstallation: vi.fn(),
}));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('shared/composables/useBranding', () => ({
  useBranding: () => ({ replaceInstallationName: value => value }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: api.alert }));
vi.mock('js-cookie', () => ({ default: { get: api.cookie } }));
vi.mock('customDashboard/helper/pushPermissionHelp', () => ({
  getPushPermissionHelpPlatform: api.platform,
}));
vi.mock('customDashboard/composables/usePwaInstallation', async () => {
  const { ref: state } = await import('vue');
  const status = state('unavailable');
  return {
    status,
    getInstallationPlatform: api.platform,
    isEmbeddedBrowser: api.embedded,
    usePwaInstallation: () => ({
      status,
      busy: state(false),
      promptInstall: api.install,
      checkInstallability: api.checkInstallation,
    }),
  };
});
import { status } from 'customDashboard/composables/usePwaInstallation';
import { startPushSession } from 'customDashboard/helper/pushSession';
import PwaMobileInstallPromotion from 'customDashboard/components/pwa/PwaMobileInstallPromotion.vue';
import PwaInstallationCard from 'customDashboard/components/pwa/PwaInstallationCard.vue';
import PushDeviceDiagnostics from 'customDashboard/components/pwa/PushDeviceDiagnostics.vue';

const options = {
  global: {
    stubs: {
      TeleportWithDirection: { template: '<div><slot /></div>' },
      OnClickOutside: { template: '<div><slot /></div>' },
      Button: {
        props: ['label', 'disabled'],
        template:
          '<button type="button" :disabled="disabled">{{ label }}</button>',
      },
    },
  },
};
const action = (wrapper, key) =>
  wrapper.findAll('button').find(button => button.text().includes(key));
const renderPromotion = () =>
  mount(PwaMobileInstallPromotion, {
    ...options,
    props: {
      user: { id: 7, accounts: [{ id: 2, status: 'active' }] },
      accountId: 2,
      ready: true,
    },
  });
const device = () => ({
  disabled: ref(false),
  activity: ref(null),
  test: vi.fn().mockResolvedValue({ kind: 'accepted' }),
  inspect: vi.fn().mockResolvedValue({ kind: 'ready' }),
  activate: vi.fn().mockResolvedValue({ status: 'subscribed' }),
});

describe('shared installation and assisted diagnostics UI', () => {
  beforeEach(() => {
    localStorage.clear();
    api.platform.mockReturnValue('ANDROID');
    api.embedded.mockReturnValue(false);
    api.cookie.mockReturnValue('authenticated');
    api.install.mockResolvedValue({ outcome: 'dismissed' });
    api.checkInstallation.mockResolvedValue();
    startPushSession();
    status.value = 'unavailable';
    Object.defineProperty(HTMLDialogElement.prototype, 'showModal', {
      configurable: true,
      value() {
        this.setAttribute('open', '');
      },
    });
    Object.defineProperty(HTMLDialogElement.prototype, 'close', {
      configurable: true,
      value() {
        this.removeAttribute('open');
        this.dispatchEvent(new Event('close'));
      },
    });
  });

  it('offers manual Android help without interpreting a missing event as installed', async () => {
    const wrapper = renderPromotion();
    expect(wrapper.text()).toContain('PWA_PROMOTION_TITLE');
    expect(action(wrapper, 'PWA_MOBILE_INSTALL_ACTION')).toBeUndefined();
    await action(wrapper, 'PWA_HOW_INSTALL_ACTION').trigger('click');
    expect(wrapper.text()).toContain('PWA_HELP_ANDROID_1');
    expect(wrapper.find('ol').findAll('li')).toHaveLength(3);
    await action(wrapper, 'PUSH_LATER_ACTION').trigger('click');
    expect(wrapper.text()).not.toContain('PWA_PROMOTION_TITLE');
    expect(localStorage.getItem('chatwoot:install-promotion:v1:7')).toBe(
      'dismissed'
    );
    wrapper.unmount();
  });

  it('offers native installation on Android and dismisses promotion after cancellation', async () => {
    status.value = 'available';
    const wrapper = renderPromotion();
    await action(wrapper, 'PWA_MOBILE_INSTALL_ACTION').trigger('click');
    await flushPromises();
    expect(api.install).toHaveBeenCalledOnce();
    expect(wrapper.text()).not.toContain('PWA_PROMOTION_TITLE');
    wrapper.unmount();
  });

  it('shows iOS numbered help and embedded-browser address copying', async () => {
    api.platform.mockReturnValue('IOS');
    api.embedded.mockReturnValue(true);
    status.value = 'embedded_instructions';
    const clipboard = vi.fn().mockResolvedValue();
    Object.defineProperty(navigator, 'clipboard', {
      configurable: true,
      value: { writeText: clipboard },
    });
    const wrapper = renderPromotion();
    await action(wrapper, 'PWA_HOW_INSTALL_ACTION').trigger('click');
    expect(wrapper.text()).toContain('PWA_HELP_IOS_2');
    expect(wrapper.text()).toContain('PWA_EMBEDDED_HELP');
    await action(wrapper, 'PWA_COPY_ACTION').trigger('click');
    expect(clipboard).toHaveBeenCalledWith(`${window.location.origin}/`);
    wrapper.unmount();
  });

  it('keeps installation help in desktop preferences, without a mobile promotion', async () => {
    api.platform.mockReturnValue('DESKTOP');
    const promotion = renderPromotion();
    expect(promotion.text()).not.toContain('PWA_PROMOTION_TITLE');
    promotion.unmount();
    const settings = mount(PwaInstallationCard, options);
    await action(settings, 'PWA_HOW_INSTALL_ACTION').trigger('click');
    expect(settings.text()).toContain('PWA_HELP_DESKTOP_1');
    settings.unmount();
  });

  it('offers no native installation for a verified icon error', () => {
    status.value = 'icon_error';
    const wrapper = renderPromotion();
    expect(action(wrapper, 'PWA_MOBILE_INSTALL_ACTION')).toBeUndefined();
    wrapper.unmount();
  });

  it('asks Received/Not received and rechecks without automatically resending', async () => {
    const current = device();
    const wrapper = mount(PushDeviceDiagnostics, {
      ...options,
      props: { device: current },
    });
    await wrapper.vm.test();
    await flushPromises();
    expect(wrapper.text()).toContain('PUSH_DIAGNOSTIC_ACCEPTED');
    expect(wrapper.get('dialog').attributes('aria-label')).toContain(
      'PUSH_TEST_ACTION'
    );
    await action(wrapper, 'PUSH_NOT_RECEIVED_ACTION').trigger('click');
    await flushPromises();
    expect(current.inspect).toHaveBeenCalledWith({ recoverPermission: false });
    expect(current.test).toHaveBeenCalledOnce();
    expect(wrapper.text()).toContain('PUSH_DIAGNOSTIC_READY');
    expect(wrapper.text()).toContain('PUSH_HELP_SYSTEM');
    wrapper.unmount();
  });

  it('Received closes the accessible dialog', async () => {
    const wrapper = mount(PushDeviceDiagnostics, {
      ...options,
      props: { device: device() },
    });
    await wrapper.vm.test();
    await flushPromises();
    await action(wrapper, 'PUSH_RECEIVED_ACTION').trigger('click');
    expect(wrapper.get('dialog').attributes('open')).toBeUndefined();
    wrapper.unmount();
  });

  it('guides missing banners without another send or a native permission request', async () => {
    const current = device();
    const wrapper = mount(PushDeviceDiagnostics, {
      ...options,
      props: { device: current },
    });
    await wrapper.vm.test();
    await flushPromises();
    await action(wrapper, 'PUSH_NO_BANNER_ACTION').trigger('click');
    await flushPromises();
    expect(current.inspect).toHaveBeenCalledWith({ recoverPermission: false });
    expect(current.test).toHaveBeenCalledOnce();
    expect(current.activate).not.toHaveBeenCalled();
    expect(wrapper.text()).toContain('PUSH_DIAGNOSTIC_BANNER');
    expect(wrapper.text()).toContain('PUSH_BANNER_HELP_ANDROID');
    wrapper.unmount();
  });

  it('shows a revoked permission instead of misclassifying it as a banner setting', async () => {
    const current = device();
    current.inspect.mockResolvedValue({ kind: 'denied' });
    const wrapper = mount(PushDeviceDiagnostics, {
      ...options,
      props: { device: current },
    });
    await wrapper.vm.test();
    await flushPromises();
    await action(wrapper, 'PUSH_NO_BANNER_ACTION').trigger('click');
    await flushPromises();
    expect(wrapper.text()).toContain('PUSH_DIAGNOSTIC_DENIED');
    expect(wrapper.text()).not.toContain('PUSH_DIAGNOSTIC_BANNER');
    expect(current.test).toHaveBeenCalledOnce();
    wrapper.unmount();
  });

  it('shows iOS Home Screen and system banner guidance in the same diagnostic', async () => {
    api.platform.mockReturnValue('IOS');
    const current = device();
    const wrapper = mount(PushDeviceDiagnostics, {
      ...options,
      props: { device: current },
    });
    await wrapper.vm.test();
    await action(wrapper, 'PUSH_NO_BANNER_ACTION').trigger('click');
    await flushPromises();
    expect(wrapper.text()).toContain('PUSH_BANNER_HELP_IOS');
    expect(wrapper.text()).not.toContain('PUSH_BANNER_HELP_ANDROID');
    expect(current.activate).not.toHaveBeenCalled();
    wrapper.unmount();
  });

  it.each([
    'denied',
    'default',
    'opt_out',
    'requires_install',
    'unsupported',
    'limited',
    'session',
    'invalid',
    'delivery',
    'connection',
    'timeout',
    'insecure_context',
    'unsupported_browser',
    'missing_configuration',
  ])('opens appropriate guidance for %s without another test', async kind => {
    const current = device();
    current.test.mockResolvedValue({ kind });
    const wrapper = mount(PushDeviceDiagnostics, {
      ...options,
      props: { device: current },
    });
    await wrapper.vm.test();
    await flushPromises();
    expect(wrapper.text()).toContain(`PUSH_DIAGNOSTIC_${kind.toUpperCase()}`);
    expect(current.activate).not.toHaveBeenCalled();
    expect(current.test).toHaveBeenCalledOnce();
    if (kind === 'denied')
      expect(wrapper.text()).toContain('PUSH_RECHECK_ACTION');
    if (kind === 'requires_install')
      expect(wrapper.text()).toContain('PWA_HELP_ANDROID_1');
    wrapper.unmount();
  });

  it('requires explicit activation and a separate click to send the test', async () => {
    const current = device();
    current.test.mockResolvedValue({ kind: 'default' });
    const wrapper = mount(PushDeviceDiagnostics, {
      ...options,
      props: { device: current },
    });
    await wrapper.vm.test();
    await flushPromises();
    const pending = action(wrapper, 'PUSH_ALLOW_ACTION').trigger('click');
    expect(current.activate).toHaveBeenCalledOnce();
    await pending;
    await flushPromises();
    expect(wrapper.text()).toContain('PUSH_DIAGNOSTIC_READY');
    expect(current.test).toHaveBeenCalledOnce();
    wrapper.unmount();
  });

  it('recovers a 404 subscription only on click, then waits for a new explicit test', async () => {
    const current = device();
    current.test.mockResolvedValue({ kind: 'missing' });
    const wrapper = mount(PushDeviceDiagnostics, {
      ...options,
      props: { device: current },
    });
    await wrapper.vm.test();
    await flushPromises();
    await action(wrapper, 'PUSH_RECOVER_ACTION').trigger('click');
    expect(current.inspect).toHaveBeenCalledWith({ recoverPermission: true });
    expect(current.test).toHaveBeenCalledOnce();
    wrapper.unmount();
  });

  it('does not reopen a diagnostic closed while a second test was pending', async () => {
    const current = device();
    const wrapper = mount(PushDeviceDiagnostics, {
      ...options,
      props: { device: current },
    });
    await wrapper.vm.test();
    await flushPromises();
    await action(wrapper, 'PUSH_NOT_RECEIVED_ACTION').trigger('click');
    await flushPromises();
    let finish;
    current.test.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          finish = resolve;
        })
    );
    await action(wrapper, 'PUSH_TEST_ACTION').trigger('click');
    wrapper.get('dialog').element.close();
    finish({ kind: 'accepted' });
    await flushPromises();
    expect(wrapper.get('dialog').attributes('open')).toBeUndefined();
    expect(wrapper.text()).not.toContain('PUSH_DIAGNOSTIC_ACCEPTED');
    await wrapper.vm.test();
    await flushPromises();
    expect(wrapper.get('dialog').attributes('open')).toBeDefined();
    wrapper.unmount();
  });

  it('ignores a late initial test after unmount', async () => {
    const current = device();
    let finish;
    current.test.mockImplementation(
      () =>
        new Promise(resolve => {
          finish = resolve;
        })
    );
    const wrapper = mount(PushDeviceDiagnostics, {
      ...options,
      props: { device: current },
    });
    const pending = wrapper.vm.test();
    wrapper.unmount();
    finish({ kind: 'accepted' });
    await pending;
    expect(api.alert).not.toHaveBeenCalled();
  });

  it('offers an explicit installation recheck and blocks duplicate checks while checking', async () => {
    status.value = 'connection_timeout';
    const wrapper = mount(PwaInstallationCard, options);
    expect(api.checkInstallation).toHaveBeenCalledOnce();
    expect(wrapper.text()).toContain('PWA_INSTALL_STATUS_CONNECTION_TIMEOUT');
    await action(wrapper, 'PWA_RECHECK_ACTION').trigger('click');
    expect(api.checkInstallation).toHaveBeenCalledTimes(2);
    status.value = 'checking';
    await flushPromises();
    expect(
      action(wrapper, 'PWA_RECHECK_ACTION').attributes('disabled')
    ).toBeDefined();
    wrapper.unmount();
  });
});
