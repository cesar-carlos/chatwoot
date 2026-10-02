import { mount, flushPromises } from '@vue/test-utils';
import { defineComponent } from 'vue';
import { beforeEach, describe, expect, it, vi } from 'vitest';
const api = vi.hoisted(() => ({
  environment: vi.fn(),
  ensure: vi.fn(),
  activate: vi.fn(),
  deactivate: vi.fn(),
  test: vi.fn(),
  alert: vi.fn(),
  cookie: vi.fn(),
}));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/composables', () => ({ useAlert: api.alert }));
vi.mock('js-cookie', () => ({ default: { get: api.cookie } }));
vi.mock('customDashboard/helper/pushHelper', () => ({
  getPushEnvironment: api.environment,
  ensurePushSubscription: api.ensure,
  requestAndSubscribe: api.activate,
  unsubscribePush: api.deactivate,
}));
vi.mock('customDashboard/api/notificationSubscription', () => ({
  testBrowserSubscription: api.test,
}));
import { usePushDevice } from 'customDashboard/composables/usePushDevice';
import {
  beginPushLogout,
  startPushSession,
} from 'customDashboard/helper/pushSession';

const subscribed = {
  status: 'subscribed',
  permission: 'granted',
  subscription: { endpoint: 'https://push.example.test/device' },
};
const render = () =>
  mount(
    defineComponent({
      setup: () => usePushDevice(),
      template: '<div />',
    })
  );

describe('shared Push device state', () => {
  beforeEach(() => {
    api.cookie.mockReturnValue('authenticated');
    startPushSession();
    api.environment.mockReturnValue({
      supported: true,
      permission: 'default',
      status: 'default',
    });
    api.activate.mockResolvedValue(subscribed);
    api.ensure.mockResolvedValue(subscribed);
    api.test.mockResolvedValue({});
  });

  it('does not prompt or subscribe on mount before permission is granted', () => {
    const wrapper = render();
    expect(api.activate).not.toHaveBeenCalled();
    expect(api.ensure).not.toHaveBeenCalled();
    expect(wrapper.vm.status).toBe('default');
    wrapper.unmount();
  });

  it('waits for a confirmed subscription before allowing a test', async () => {
    api.environment.mockReturnValue({
      supported: true,
      permission: 'granted',
      status: 'granted',
    });
    let finish;
    api.ensure.mockImplementation(
      () =>
        new Promise(resolve => {
          finish = resolve;
        })
    );
    const wrapper = render();
    expect(wrapper.vm.status).toBe('checking');
    expect(wrapper.vm.disabled).toBe(true);
    wrapper.vm.test();
    expect(api.test).not.toHaveBeenCalled();
    finish(subscribed);
    await flushPromises();
    expect(wrapper.vm.endpoint).toBe(subscribed.subscription.endpoint);
    await wrapper.vm.test();
    expect(api.alert).toHaveBeenCalledWith(
      'PROFILE_SETTINGS.FORM.NOTIFICATIONS.PUSH_TEST_ACCEPTED'
    );
    wrapper.unmount();
  });

  it('invokes permission during the click and serializes actions across surfaces', async () => {
    let finish;
    api.activate.mockImplementation(
      () =>
        new Promise(resolve => {
          finish = resolve;
        })
    );
    const first = render();
    const second = render();
    const pending = first.vm.activate();
    expect(api.activate).toHaveBeenCalledOnce();
    await second.vm.activate();
    expect(api.activate).toHaveBeenCalledOnce();
    finish(subscribed);
    await pending;
    expect(first.vm.subscribed).toBe(true);
    expect(second.vm.subscribed).toBe(true);
    first.unmount();
    second.unmount();
  });

  it('exposes failure and permits a subsequent explicit retry', async () => {
    api.activate.mockRejectedValueOnce(new Error('provider failure'));
    const wrapper = render();
    await wrapper.vm.activate();
    expect(wrapper.vm.status).toBe('error');
    expect(wrapper.vm.subscribed).toBe(false);
    expect(wrapper.vm.busy).toBe(false);
    await wrapper.vm.activate();
    expect(wrapper.vm.subscribed).toBe(true);
    wrapper.unmount();
  });

  it('preserves the enabled selection when local removal fails', async () => {
    const wrapper = render();
    await wrapper.vm.activate();
    api.deactivate.mockRejectedValue(new Error('local removal failed'));
    await wrapper.vm.deactivate();
    expect(wrapper.vm.subscribed).toBe(true);
    expect(api.alert).toHaveBeenCalledWith(
      'PROFILE_SETTINGS.FORM.NOTIFICATIONS.PUSH_SUBSCRIPTION_ERROR'
    );
    wrapper.unmount();
  });

  it('ignores results from a logged-out session, including after a new login', async () => {
    let finish;
    api.activate.mockImplementation(
      () =>
        new Promise(resolve => {
          finish = resolve;
        })
    );
    const wrapper = render();
    const pending = wrapper.vm.activate();
    beginPushLogout();
    api.cookie.mockReturnValue('other-user');
    startPushSession();
    finish(subscribed);
    await pending;
    expect(wrapper.vm.subscribed).toBe(false);
    expect(api.alert).not.toHaveBeenCalled();
    wrapper.unmount();
  });

  it('ignores activation results after the surface is unmounted', async () => {
    let finish;
    api.activate.mockImplementation(
      () =>
        new Promise(resolve => {
          finish = resolve;
        })
    );
    const wrapper = render();
    const pending = wrapper.vm.activate();
    wrapper.unmount();
    finish(subscribed);
    await pending;
    expect(api.alert).not.toHaveBeenCalled();
  });

  it('recovers a previously blocked permission but not permission granted for Pop-up', async () => {
    const wrapper = render();
    api.environment.mockReturnValue({
      supported: true,
      status: 'granted',
      permission: 'granted',
    });
    await wrapper.vm.refresh();
    expect(api.ensure).toHaveBeenLastCalledWith({ recoverPermission: false });
    api.environment.mockReturnValue({
      supported: true,
      status: 'denied',
      permission: 'denied',
    });
    await wrapper.vm.refresh();
    api.environment.mockReturnValue({
      supported: true,
      status: 'granted',
      permission: 'granted',
    });
    await wrapper.vm.refresh();
    expect(api.ensure).toHaveBeenLastCalledWith({ recoverPermission: true });
    wrapper.unmount();
  });
});
