import { beforeEach, describe, expect, it, vi } from 'vitest';
import { shallowMount } from '@vue/test-utils';
import { createStore } from 'vuex';

vi.mock('dashboard/composables', () => ({
  useAlert: vi.fn(),
}));

vi.mock('dashboard/api/inboxes', () => ({
  default: {},
}));

import WavoipCallingPage from '../WavoipCallingPage.vue';

describe('WavoipCallingPage', () => {
  let store;
  let fetchInboxItem;
  let updateInbox;

  const mountPage = (inboxOverrides = {}) =>
    shallowMount(WavoipCallingPage, {
      global: {
        plugins: [store],
        mocks: {
          $t: key => key,
        },
        stubs: {
          SettingsFieldSection: true,
          SettingsToggleSection: true,
          SelectInput: true,
          WavoipDevicePanel: true,
          NextButton: true,
          Spinner: true,
        },
      },
      props: {
        inbox: {
          id: 1,
          voice_enabled: true,
          provider_config: {
            incoming_call_include_administrators: true,
            incoming_call_offline_fallback:
              'assignee_or_inbox_members_and_administrators',
            incoming_call_notify_busy_agents: false,
            ring_timeout_seconds: 0,
          },
          ...inboxOverrides,
        },
      },
    });

  beforeEach(() => {
    fetchInboxItem = vi.fn().mockResolvedValue({});
    updateInbox = vi.fn().mockResolvedValue({});

    store = createStore({
      actions: {
        'inboxes/fetchInboxItem': fetchInboxItem,
        'inboxes/updateInbox': updateInbox,
      },
      getters: {
        'inboxes/getInbox': () => inboxId => ({
          id: inboxId,
          provider_config: {
            incoming_call_include_administrators: true,
            incoming_call_offline_fallback:
              'assignee_or_inbox_members_and_administrators',
            incoming_call_notify_busy_agents: false,
            ring_timeout_seconds: 30,
          },
        }),
      },
    });
  });

  it('fetches inbox state from the server before saving call routing', async () => {
    const wrapper = mountPage();
    const callOrder = [];

    fetchInboxItem.mockImplementation(async () => {
      callOrder.push('fetch');
    });
    updateInbox.mockImplementation(async () => {
      callOrder.push('update');
    });

    await wrapper.vm.saveCallRouting({
      incoming_call_include_administrators: false,
      incoming_call_offline_fallback: 'assignee',
      incoming_call_notify_busy_agents: true,
      ring_timeout_seconds: 60,
    });

    expect(fetchInboxItem).toHaveBeenCalledWith(expect.anything(), 1);
    expect(callOrder[0]).toBe('fetch');
    expect(callOrder[1]).toBe('update');
    expect(updateInbox).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({
        channel: {
          provider_config: expect.objectContaining({
            incoming_call_offline_fallback: 'assignee',
            ring_timeout_seconds: 60,
            incoming_call_notify_busy_agents: true,
          }),
        },
      })
    );
  });

  it('forces include_admins false when offline fallback is none', async () => {
    const wrapper = mountPage();

    await wrapper.vm.handleOfflineFallbackChange('none');

    expect(wrapper.vm.includeAdministrators).toBe(false);
    expect(updateInbox).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({
        channel: {
          provider_config: expect.objectContaining({
            incoming_call_offline_fallback: 'none',
            incoming_call_include_administrators: false,
          }),
        },
      })
    );
  });
});
