import { beforeEach, describe, expect, it, vi } from 'vitest';
import { mount, flushPromises } from '@vue/test-utils';
const api = vi.hoisted(() => ({
  ensure: vi.fn(),
  subscribe: vi.fn(),
  unsubscribe: vi.fn(),
  test: vi.fn(),
  alert: vi.fn(),
}));
vi.mock('dashboard/composables', () => ({ useAlert: api.alert }));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('shared/composables/useBranding', () => ({
  useBranding: () => ({ replaceInstallationName: text => text }),
}));
vi.mock('customDashboard/helper/pushHelper', () => ({
  getPushEnvironment: () => ({
    supported: true,
    permission: 'granted',
    status: 'granted',
  }),
  isPushOptedOut: () => false,
  ensurePushSubscription: api.ensure,
  requestAndSubscribe: api.subscribe,
  unsubscribePush: api.unsubscribe,
}));
vi.mock('customDashboard/api/notificationSubscription', () => ({
  testBrowserSubscription: api.test,
}));
vi.mock('customDashboard/composables/usePwaInstallation', async () => {
  const { ref } = await import('vue');
  return {
    getInstallationPlatform: () => 'DESKTOP',
    isEmbeddedBrowser: () => false,
    usePwaInstallation: () => ({
      status: ref('installed'),
      checkInstallability: vi.fn(),
    }),
  };
});
import PwaDeviceSettings from '../PwaDeviceSettings.vue';
import { startPushSession } from 'customDashboard/helper/pushSession';

const render = () =>
  mount(PwaDeviceSettings, {
    global: {
      stubs: {
        FluentIcon: true,
        TeleportWithDirection: { template: '<div><slot /></div>' },
        OnClickOutside: { template: '<div><slot /></div>' },
        ToggleSwitch: {
          props: ['disabled', 'modelValue'],
          emits: ['change', 'update:modelValue'],
          template:
            '<button data-test="toggle" :disabled="disabled" @click="$emit(\'update:modelValue\', !modelValue); $emit(\'change\')">Toggle</button>',
        },
        Button: {
          props: ['label', 'disabled'],
          template: '<button :disabled="disabled">{{ label }}</button>',
        },
      },
    },
  });
const subscribed = {
  status: 'subscribed',
  permission: 'granted',
  subscription: { endpoint: 'https://push.example.test/device' },
};

describe('PWA device diagnostics UI', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    startPushSession();
    api.ensure.mockResolvedValue(subscribed);
    api.test.mockResolvedValue({ data: { accepted: true } });
    Object.defineProperty(HTMLDialogElement.prototype, 'showModal', {
      configurable: true,
      value() {
        this.setAttribute('open', '');
      },
    });
  });
  it('shows checking and disables editing until the subscription is confirmed', async () => {
    let finish;
    api.ensure.mockImplementation(
      () =>
        new Promise(resolve => {
          finish = resolve;
        })
    );
    const wrapper = render();
    expect(wrapper.text()).toContain('PUSH_STATUS_CHECKING');
    expect(wrapper.find('[data-test="toggle"]').exists()).toBe(false);
    expect(
      wrapper
        .findAll('button')
        .some(button => button.text().includes('PUSH_TEST_ACTION'))
    ).toBe(false);
    finish(subscribed);
    await flushPromises();
    expect(wrapper.text()).toContain('PUSH_TEST_ACTION');
    wrapper.unmount();
  });
  it('serializes diagnostic clicks and explains accepted does not mean displayed', async () => {
    let finish;
    api.test.mockImplementation(
      () =>
        new Promise(resolve => {
          finish = resolve;
        })
    );
    const wrapper = render();
    await flushPromises();
    const button = wrapper
      .findAll('button')
      .find(candidate => candidate.text().includes('PUSH_TEST_ACTION'));
    await button.trigger('click');
    await button.trigger('click');
    expect(api.test).toHaveBeenCalledOnce();
    finish({ data: { accepted: true } });
    await flushPromises();
    expect(wrapper.text()).toContain('PUSH_DIAGNOSTIC_ACCEPTED');
    wrapper.unmount();
  });
});
