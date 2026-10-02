import { mount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import { describe, expect, it, vi } from 'vitest';
import NotificationPreferences from 'dashboard/routes/dashboard/settings/profile/NotificationPreferences.vue';

const deviceStub = {
  name: 'PwaDeviceSettings',
  props: ['pushPreferencesReady', 'selectedPushFlags'],
  template: '<div />',
};
const render = request => {
  const store = createStore({
    state: { accountId: 1, flags: [] },
    getters: {
      getCurrentAccountId: state => state.accountId,
      'userNotificationSettings/getSelectedPushFlags': state => state.flags,
      'userNotificationSettings/getSelectedEmailFlags': () => [],
      getUISettings: () => ({}),
      'accounts/isFeatureEnabledonAccount': () => () => false,
    },
    mutations: {
      account: (state, accountId) => {
        state.accountId = accountId;
      },
      flags: (state, flags) => {
        state.flags = flags;
      },
    },
    actions: {
      'userNotificationSettings/get': async ({ commit }, accountId) => {
        commit('flags', await request(accountId));
      },
    },
  });
  const wrapper = mount(NotificationPreferences, {
    global: {
      plugins: [store],
      stubs: {
        PwaDeviceSettings: deviceStub,
        TableHeaderCell: true,
        CheckBox: true,
        NextButton: true,
      },
    },
  });
  return { wrapper, store, device: () => wrapper.findComponent(deviceStub) };
};

describe('per-account event selection passed to the device', () => {
  it('does not present unloaded preferences as an empty saved selection', async () => {
    let finish;
    const request = vi.fn(
      () =>
        new Promise(resolve => {
          finish = resolve;
        })
    );
    const { wrapper, device } = render(request);
    expect(device().props('pushPreferencesReady')).toBe(false);
    finish(['push_conversation_assignment']);
    await flushPromises();
    expect(device().props('pushPreferencesReady')).toBe(true);
    expect(device().props('selectedPushFlags')).toEqual([
      'push_conversation_assignment',
    ]);
    expect(
      wrapper
        .get('#profile-settings-notification-events')
        .attributes('tabindex')
    ).toBe('-1');
    wrapper.unmount();
  });
  it('keeps the empty selection unknown if loading fails', async () => {
    const { wrapper, device } = render(
      vi.fn().mockRejectedValue(new Error('offline'))
    );
    await flushPromises();
    expect(wrapper.vm.preferencesLoadError).toBe(true);
    expect(device().props('pushPreferencesReady')).toBe(false);
    wrapper.unmount();
  });
  it('hides guidance during saving and while a different account is loading', async () => {
    let finish;
    const request = vi
      .fn()
      .mockResolvedValueOnce([])
      .mockImplementationOnce(
        () =>
          new Promise(resolve => {
            finish = resolve;
          })
      );
    const { wrapper, store, device } = render(request);
    await flushPromises();
    expect(device().props('pushPreferencesReady')).toBe(true);
    wrapper.vm.notificationSettingsUpdating = true;
    await flushPromises();
    expect(device().props('pushPreferencesReady')).toBe(false);
    wrapper.vm.notificationSettingsUpdating = false;
    store.commit('account', 2);
    await flushPromises();
    expect(device().props('pushPreferencesReady')).toBe(false);
    finish(['push_conversation_mention']);
    await flushPromises();
    expect(device().props('pushPreferencesReady')).toBe(true);
    expect(device().props('selectedPushFlags')).toEqual([
      'push_conversation_mention',
    ]);
    expect(request).toHaveBeenLastCalledWith(2);
    wrapper.unmount();
  });
});
