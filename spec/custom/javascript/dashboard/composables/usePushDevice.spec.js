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
  optedOut: vi.fn(),
}));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/composables', () => ({ useAlert: api.alert }));
vi.mock('js-cookie', () => ({ default: { get: api.cookie } }));
vi.mock('customDashboard/helper/pushHelper', () => ({
  getPushEnvironment: api.environment,
  isPushOptedOut: api.optedOut,
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
    api.optedOut.mockReturnValue(false);
    api.test.mockResolvedValue({ data: { accepted: true } });
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
    api.ensure.mockImplementationOnce(
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
    expect(await wrapper.vm.test()).toEqual({ kind: 'accepted' });
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

  it.each([
    [true, 'denied', 'denied'],
    [true, 'default', 'default'],
    [false, 'default', 'requires_install'],
    [false, 'granted', 'unsupported'],
  ])(
    'does not send or request permission with environment %s/%s/%s',
    async (supported, permission, status) => {
      const wrapper = render();
      await wrapper.vm.activate();
      api.ensure.mockClear();
      api.environment.mockReturnValue({ supported, permission, status });
      expect(await wrapper.vm.test()).toEqual({ kind: status });
      expect(api.ensure).not.toHaveBeenCalled();
      expect(api.test).not.toHaveBeenCalled();
      expect(api.activate).toHaveBeenCalledOnce();
      wrapper.unmount();
    }
  );

  it('preserves opt-out even during explicit recovery and testing', async () => {
    const wrapper = render();
    api.environment.mockReturnValue({
      supported: true,
      permission: 'granted',
      status: 'granted',
    });
    api.optedOut.mockReturnValue(true);
    expect(await wrapper.vm.inspect({ recoverPermission: true })).toEqual({
      kind: 'opt_out',
    });
    expect(await wrapper.vm.test()).toEqual({ kind: 'opt_out' });
    expect(api.ensure).not.toHaveBeenCalled();
    expect(api.test).not.toHaveBeenCalled();
    wrapper.unmount();
  });

  it('uses the freshly confirmed endpoint, not the previously displayed subscription', async () => {
    const wrapper = render();
    await wrapper.vm.activate();
    api.environment.mockReturnValue({
      supported: true,
      permission: 'granted',
      status: 'granted',
    });
    api.ensure.mockResolvedValue({
      ...subscribed,
      subscription: { endpoint: 'https://push.example.test/new-device' },
    });
    expect(await wrapper.vm.test()).toEqual({ kind: 'accepted' });
    expect(api.test).toHaveBeenCalledWith(
      'https://push.example.test/new-device'
    );
    expect(api.ensure).toHaveBeenCalledWith({ recoverPermission: false });
    wrapper.unmount();
  });

  it('offers explicit recovery for a missing subscription without sending a test', async () => {
    const wrapper = render();
    api.environment.mockReturnValue({
      supported: true,
      permission: 'granted',
      status: 'granted',
    });
    api.ensure.mockResolvedValue({
      status: 'unsubscribed',
      permission: 'granted',
    });
    expect(await wrapper.vm.test()).toMatchObject({ kind: 'missing' });
    expect(api.test).not.toHaveBeenCalled();
    api.ensure.mockResolvedValue(subscribed);
    expect(await wrapper.vm.inspect({ recoverPermission: true })).toMatchObject(
      { kind: 'ready' }
    );
    expect(api.test).not.toHaveBeenCalled();
    wrapper.unmount();
  });

  it.each([
    ['denied', false, 'denied'],
    ['granted', true, 'opt_out'],
  ])(
    'rechecks permission and opt-out after awaiting the worker (%s/%s)',
    async (permission, optedOut, kind) => {
      const wrapper = render();
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
      const pending = wrapper.vm.test();
      await wrapper.vm.activate();
      expect(api.activate).not.toHaveBeenCalled();
      api.environment.mockReturnValue({
        supported: true,
        permission,
        status: permission,
      });
      api.optedOut.mockReturnValue(optedOut);
      finish(subscribed);
      expect(await pending).toEqual({ kind });
      expect(api.test).not.toHaveBeenCalled();
      wrapper.unmount();
    }
  );

  it.each([
    [401, 'session'],
    [403, 'session'],
    [404, 'missing'],
    [422, 'invalid'],
    [429, 'limited'],
    [502, 'delivery'],
  ])(
    'classifies HTTP %s without retry or permission prompt',
    async (status, kind) => {
      const wrapper = render();
      api.environment.mockReturnValue({
        supported: true,
        permission: 'granted',
        status: 'granted',
      });
      api.test.mockRejectedValue({ response: { status } });
      expect(await wrapper.vm.test()).toEqual({ kind });
      expect(api.test).toHaveBeenCalledOnce();
      expect(api.activate).not.toHaveBeenCalled();
      expect(wrapper.vm.busy).toBe(false);
      wrapper.unmount();
    }
  );

  it.each([
    [{}, 'connection'],
    [{ code: 'ECONNABORTED' }, 'timeout'],
    [{ code: 'PUSH_WORKER_TIMEOUT' }, 'timeout'],
  ])(
    'reports connection/timeout failures without locking the UI',
    async (error, kind) => {
      const wrapper = render();
      api.environment.mockReturnValue({
        supported: true,
        permission: 'granted',
        status: 'granted',
      });
      api.ensure.mockRejectedValue(error);
      expect(await wrapper.vm.test()).toEqual({ kind });
      expect(wrapper.vm.disabled).toBe(false);
      expect(api.test).not.toHaveBeenCalled();
      wrapper.unmount();
    }
  );

  it('requires accepted true and never equates an HTTP success with display', async () => {
    const wrapper = render();
    api.environment.mockReturnValue({
      supported: true,
      permission: 'granted',
      status: 'granted',
    });
    api.test.mockResolvedValue({ data: { accepted: false } });
    expect(await wrapper.vm.test()).toEqual({ kind: 'delivery' });
    expect(api.alert).not.toHaveBeenCalled();
    wrapper.unmount();
  });

  it('drops a diagnostic after logout or disposal before the worker completes', async () => {
    const wrapper = render();
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
    const pending = wrapper.vm.test();
    beginPushLogout();
    api.cookie.mockReturnValue('new-user');
    startPushSession();
    finish(subscribed);
    expect(await pending).toBeNull();
    expect(api.test).not.toHaveBeenCalled();
    wrapper.unmount();
  });

  it('does not return an accepted result after unmount while delivery is pending', async () => {
    const wrapper = render();
    api.environment.mockReturnValue({
      supported: true,
      permission: 'granted',
      status: 'granted',
    });
    let finish;
    api.test.mockImplementation(
      () =>
        new Promise(resolve => {
          finish = resolve;
        })
    );
    const pending = wrapper.vm.test();
    await flushPromises();
    wrapper.unmount();
    finish({ data: { accepted: true } });
    expect(await pending).toBeNull();
  });

  it('checks permission again after the provider responds', async () => {
    const wrapper = render();
    api.environment.mockReturnValue({
      supported: true,
      permission: 'granted',
      status: 'granted',
    });
    let finish;
    api.test.mockImplementation(
      () =>
        new Promise(resolve => {
          finish = resolve;
        })
    );
    const pending = wrapper.vm.test();
    await flushPromises();
    api.environment.mockReturnValue({
      supported: true,
      permission: 'denied',
      status: 'denied',
    });
    finish({ data: { accepted: true } });
    expect(await pending).toEqual({ kind: 'denied' });
    expect(wrapper.vm.subscribed).toBe(false);
    wrapper.unmount();
  });

  it('allows the remaining surface to finish checking if the first surface unmounts', async () => {
    api.environment.mockReturnValue({
      supported: true,
      permission: 'granted',
      status: 'granted',
    });
    let finish;
    api.ensure.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          finish = resolve;
        })
    );
    const first = render();
    const second = render();
    first.unmount();
    finish(subscribed);
    await flushPromises();
    expect(second.vm.subscribed).toBe(true);
    expect(second.vm.disabled).toBe(false);
    second.unmount();
  });
});
