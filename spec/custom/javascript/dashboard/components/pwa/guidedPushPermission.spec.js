import { mount, flushPromises } from '@vue/test-utils';
import { beforeEach, describe, expect, it, vi } from 'vitest';
const api = vi.hoisted(() => ({
  environment: vi.fn(),
  ensure: vi.fn(),
  activate: vi.fn(),
  cookie: vi.fn(),
  route: vi.fn(),
  alert: vi.fn(),
}));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('vue-router', () => ({ useRouter: () => ({ push: api.route }) }));
vi.mock('shared/composables/useBranding', () => ({
  useBranding: () => ({ replaceInstallationName: value => value }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: api.alert }));
vi.mock('js-cookie', () => ({ default: { get: api.cookie } }));
vi.mock('customDashboard/helper/pushHelper', () => ({
  getPushEnvironment: api.environment,
  isPwaStandalone: () => true,
  isPushOptedOut: () =>
    localStorage.getItem('chatwoot_push_enabled') === 'false',
  ensurePushSubscription: api.ensure,
  requestAndSubscribe: api.activate,
  unsubscribePush: vi.fn(),
}));
vi.mock('customDashboard/api/notificationSubscription', () => ({
  testBrowserSubscription: vi.fn(),
}));
vi.mock('customDashboard/composables/usePwaInstallation', async () => {
  const { ref } = await import('vue');
  return {
    usePwaInstallation: () => ({
      status: ref('installed'),
      promptInstall: vi.fn(),
      checkInstallability: vi.fn(),
    }),
  };
});
import PwaPushInvitation from 'customDashboard/components/pwa/PwaPushInvitation.vue';
import PwaDeviceSettings from 'customDashboard/components/pwa/PwaDeviceSettings.vue';
import { startPushSession } from 'customDashboard/helper/pushSession';
import { pushInvitationKey } from 'customDashboard/composables/usePwaPushInvitation';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

const subscribed = {
  status: 'subscribed',
  permission: 'granted',
  subscription: { endpoint: 'https://push.example.test/device' },
};
const user = { id: 7, accounts: [{ id: 2, status: 'active' }] };
const render = (component = PwaPushInvitation) =>
  mount(component, {
    attachTo: document.body,
    props:
      component === PwaPushInvitation
        ? { user, accountId: 2, ready: true }
        : {},
    global: {
      stubs: {
        FluentIcon: true,
        OnClickOutside: {
          name: 'OnClickOutside',
          emits: ['trigger'],
          template: '<div><slot /></div>',
        },
        TeleportWithDirection: { template: '<div><slot /></div>' },
        Button: {
          props: ['label', 'disabled'],
          template:
            '<button type="button" :disabled="disabled">{{ label }}</button>',
        },
        ToggleSwitch: true,
      },
    },
  });
const action = (wrapper, key) =>
  wrapper.findAll('button').find(button => button.text().includes(key));

describe('guided notification permission UI', () => {
  beforeEach(() => {
    document.body.innerHTML = '';
    localStorage.clear();
    api.cookie.mockReturnValue('authenticated');
    startPushSession();
    api.environment.mockReturnValue({
      supported: true,
      permission: 'default',
      status: 'default',
    });
    api.activate.mockResolvedValue(subscribed);
    api.ensure.mockResolvedValue(subscribed);
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

  it('offers permission on first launch with an accessible dialog, not a native prompt', async () => {
    const wrapper = render();
    await flushPromises();
    expect(wrapper.get('dialog').attributes('aria-label')).toContain(
      'PUSH_INVITATION_TITLE'
    );
    expect(wrapper.get('dialog').attributes('open')).toBeDefined();
    expect(api.activate).not.toHaveBeenCalled();
    await action(wrapper, 'PUSH_ALLOW_ACTION').trigger('click');
    await flushPromises();
    expect(api.activate).toHaveBeenCalledOnce();
    await action(wrapper, 'PUSH_CHOOSE_EVENTS_ACTION').trigger('click');
    expect(api.route).toHaveBeenCalledWith({
      name: 'profile_settings_index',
      params: { accountId: 2 },
      hash: '#profile-settings-notifications',
    });
    wrapper.unmount();
  });

  it('dismisses without subscribing and persists the invitation after native dialog closure', async () => {
    const wrapper = render();
    await flushPromises();
    wrapper.get('dialog').element.close();
    await flushPromises();
    expect(wrapper.get('dialog').attributes('open')).toBeUndefined();
    expect(localStorage.getItem(pushInvitationKey(7))).toBe('shown');
    expect(localStorage.getItem('chatwoot_push_enabled')).toBeNull();
    expect(api.activate).not.toHaveBeenCalled();
    wrapper.unmount();
  });

  it('Not now closes the invitation, while explicit retry remains available after failure', async () => {
    api.activate.mockRejectedValueOnce(new Error('delivery failure'));
    const wrapper = render();
    await flushPromises();
    await action(wrapper, 'PUSH_ALLOW_ACTION').trigger('click');
    await flushPromises();
    expect(wrapper.text()).toContain('PUSH_SUBSCRIPTION_ERROR');
    expect(action(wrapper, 'RETRY')).toBeDefined();
    await action(wrapper, 'PUSH_LATER_ACTION').trigger('click');
    await flushPromises();
    expect(wrapper.get('dialog').attributes('open')).toBeUndefined();
    wrapper.unmount();
  });

  it('outside-click dismissal never asks for browser permission', async () => {
    const wrapper = render();
    await flushPromises();
    wrapper
      .findComponent(Dialog)
      .findComponent({ name: 'OnClickOutside' })
      .vm.$emit('trigger');
    await flushPromises();
    expect(wrapper.get('dialog').attributes('open')).toBeUndefined();
    expect(api.activate).not.toHaveBeenCalled();
    wrapper.unmount();
  });

  it('shows help instead of attempting a denied native permission request', async () => {
    api.environment.mockReturnValue({
      supported: true,
      permission: 'denied',
      status: 'denied',
    });
    const wrapper = render();
    await flushPromises();
    await action(wrapper, 'PUSH_HELP_ACTION').trigger('click');
    expect(api.activate).not.toHaveBeenCalled();
    expect(wrapper.text()).toContain('PUSH_RECHECK_ACTION');
    api.environment.mockReturnValue({
      supported: true,
      permission: 'granted',
      status: 'granted',
    });
    await action(wrapper, 'PUSH_RECHECK_ACTION').trigger('click');
    await flushPromises();
    expect(api.ensure).toHaveBeenCalledWith({ recoverPermission: true });
    expect(wrapper.text()).toContain('PUSH_CHOOSE_EVENTS_ACTION');
    wrapper.unmount();
  });

  it('settings provide a large explicit permission CTA', async () => {
    const wrapper = render(PwaDeviceSettings);
    expect(action(wrapper, 'PUSH_ALLOW_ACTION')).toBeDefined();
    await action(wrapper, 'PUSH_ALLOW_ACTION').trigger('click');
    await flushPromises();
    expect(wrapper.text()).toContain('PUSH_TEST_ACTION');
    wrapper.unmount();
  });

  it('settings explain unlocking and confirm recovery before exposing a test', async () => {
    api.environment.mockReturnValue({
      supported: true,
      permission: 'denied',
      status: 'denied',
    });
    const wrapper = render(PwaDeviceSettings);
    await action(wrapper, 'PUSH_HELP_ACTION').trigger('click');
    expect(api.activate).not.toHaveBeenCalled();
    expect(wrapper.text()).toContain('PUSH_RECHECK_ACTION');
    expect(action(wrapper, 'PUSH_TEST_ACTION')).toBeUndefined();
    api.environment.mockReturnValue({
      supported: true,
      permission: 'granted',
      status: 'granted',
    });
    await action(wrapper, 'PUSH_RECHECK_ACTION').trigger('click');
    await flushPromises();
    expect(action(wrapper, 'PUSH_TEST_ACTION')).toBeDefined();
    wrapper.unmount();
  });
});
