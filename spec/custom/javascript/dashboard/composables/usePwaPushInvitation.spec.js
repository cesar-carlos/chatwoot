import { mount } from '@vue/test-utils';
import { defineComponent, reactive, ref, nextTick } from 'vue';
import { beforeEach, describe, expect, it, vi } from 'vitest';
const environment = vi.hoisted(() => vi.fn());
const standalone = vi.hoisted(() => vi.fn());
const cookie = vi.hoisted(() => vi.fn());
vi.mock('js-cookie', () => ({ default: { get: cookie } }));
vi.mock('customDashboard/helper/pushHelper', () => ({
  getPushEnvironment: environment,
  isPwaStandalone: standalone,
  isPushOptedOut: () =>
    localStorage.getItem('chatwoot_push_enabled') === 'false',
}));
import {
  pushInvitationKey,
  usePwaPushInvitation,
} from 'customDashboard/composables/usePwaPushInvitation';
import { startPushSession } from 'customDashboard/helper/pushSession';

const render = (overrides = {}, initialStatus = 'default') => {
  const context = reactive({
    ready: true,
    user: { id: 7, accounts: [{ id: 2, status: 'active' }] },
    accountId: 2,
    ...overrides,
  });
  const status = ref(initialStatus);
  const wrapper = mount(
    defineComponent({
      setup: () => usePwaPushInvitation(context, status),
      template: '<div />',
    })
  );
  return { wrapper, context, status };
};

describe('one-time PWA Push invitation', () => {
  beforeEach(() => {
    localStorage.clear();
    document.body.innerHTML = '';
    cookie.mockReturnValue('authenticated');
    startPushSession();
    standalone.mockReturnValue(true);
    environment.mockReturnValue({ supported: true });
  });

  it('invites once per user and closing does not opt out of Push', () => {
    const { wrapper } = render();
    expect(wrapper.vm.open).toBe(true);
    expect(localStorage.getItem(pushInvitationKey(7))).toBe('shown');
    wrapper.vm.close();
    expect(localStorage.getItem('chatwoot_push_enabled')).toBeNull();
    wrapper.unmount();
    const again = render();
    expect(again.wrapper.vm.open).toBe(false);
    again.wrapper.unmount();
    const other = render({
      user: { id: 8, accounts: [{ id: 2, status: 'active' }] },
    });
    expect(other.wrapper.vm.open).toBe(true);
    other.wrapper.unmount();
  });

  it.each(['denied', 'unsubscribed'])(
    'invites for %s without a prompt',
    status => {
      const { wrapper } = render({}, status);
      expect(wrapper.vm.open).toBe(true);
      wrapper.unmount();
    }
  );

  it.each(['checking', 'subscribed', 'error'])(
    'does not invite during %s',
    status => {
      const { wrapper } = render({}, status);
      expect(wrapper.vm.open).toBe(false);
      expect(localStorage.getItem(pushInvitationKey(7))).toBeNull();
      wrapper.unmount();
    }
  );

  it('does not invite in a regular browser', () => {
    standalone.mockReturnValue(false);
    const { wrapper } = render();
    expect(wrapper.vm.open).toBe(false);
    wrapper.unmount();
  });

  it('preserves an explicit opt-out', () => {
    localStorage.setItem('chatwoot_push_enabled', 'false');
    const { wrapper } = render();
    expect(wrapper.vm.open).toBe(false);
    expect(localStorage.getItem(pushInvitationKey(7))).toBeNull();
    wrapper.unmount();
  });

  it('requires support, authentication and active membership', () => {
    cookie.mockReturnValue(undefined);
    let mounted = render();
    expect(mounted.wrapper.vm.open).toBe(false);
    mounted.wrapper.unmount();
    cookie.mockReturnValue('authenticated');
    environment.mockReturnValue({ supported: false });
    mounted = render();
    expect(mounted.wrapper.vm.open).toBe(false);
    mounted.wrapper.unmount();
    environment.mockReturnValue({ supported: true });
    mounted = render({
      user: { id: 7, accounts: [{ id: 2, status: 'inactive' }] },
    });
    expect(mounted.wrapper.vm.open).toBe(false);
    mounted.wrapper.unmount();
  });

  it('does not present repeatedly when local storage is unavailable', () => {
    const logger = vi.spyOn(console, 'error').mockImplementation(() => {});
    const storage = vi
      .spyOn(Storage.prototype, 'setItem')
      .mockImplementation(() => {
        throw new Error('storage unavailable');
      });
    const { wrapper } = render();
    expect(wrapper.vm.open).toBe(false);
    expect(logger).toHaveBeenCalledWith(
      'Push invitation storage is unavailable'
    );
    wrapper.unmount();
    storage.mockRestore();
    logger.mockRestore();
  });

  it('waits for membership to load and closes if it is revoked', async () => {
    const { wrapper, context } = render({ user: { id: 7, accounts: [] } });
    expect(wrapper.vm.open).toBe(false);
    context.user.accounts.push({ id: 2, status: 'active' });
    await nextTick();
    expect(wrapper.vm.open).toBe(true);
    context.user.accounts[0].status = 'inactive';
    await nextTick();
    expect(wrapper.vm.open).toBe(false);
    wrapper.unmount();
  });

  it('waits for onboarding to finish and for the subscription check', async () => {
    const { wrapper, context, status } = render({ ready: false }, 'checking');
    expect(wrapper.vm.open).toBe(false);
    context.ready = true;
    await nextTick();
    expect(wrapper.vm.open).toBe(false);
    status.value = 'unsubscribed';
    await nextTick();
    expect(wrapper.vm.open).toBe(true);
    wrapper.unmount();
  });

  it('waits until another dialog closes without polling', async () => {
    const dialog = document.createElement('dialog');
    dialog.setAttribute('open', '');
    document.body.appendChild(dialog);
    const { wrapper } = render();
    expect(wrapper.vm.open).toBe(false);
    dialog.removeAttribute('open');
    await vi.waitFor(() => expect(wrapper.vm.open).toBe(true));
    wrapper.unmount();
  });

  it('closes when the account becomes unavailable and isolates a different user', async () => {
    const { wrapper, context } = render();
    context.ready = false;
    await nextTick();
    expect(wrapper.vm.open).toBe(false);
    context.user = { id: 8, accounts: [{ id: 2, status: 'active' }] };
    context.ready = true;
    await nextTick();
    expect(wrapper.vm.open).toBe(true);
    expect(localStorage.getItem(pushInvitationKey(8))).toBe('shown');
    wrapper.unmount();
  });
});
