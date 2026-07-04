import { describe, expect, it, vi, beforeEach } from 'vitest';
import { shallowMount } from '@vue/test-utils';
import { createStore } from 'vuex';

vi.mock('dashboard/composables', () => ({
  useAlert: vi.fn(),
}));

import EvolutionSettingsPage from '../EvolutionSettingsPage.vue';

describe('EvolutionSettingsPage', () => {
  let store;
  let updateInbox;

  const baseProviderConfig = {
    groups_ignore: true,
    sign_msg: false,
    connection_status: 'connecting',
    import_status: 'idle',
  };

  const mountPage = (inboxOverrides = {}) =>
    shallowMount(EvolutionSettingsPage, {
      global: {
        plugins: [store],
        mocks: { $t: key => key },
        stubs: {
          SettingsFieldSection: true,
          SettingsToggleSection: true,
          SettingsAccordion: true,
          Input: true,
          NextButton: true,
          TextArea: true,
          SelectInput: true,
          EvolutionHealthPage: true,
          SingleHistoryAutomationWarning: true,
        },
      },
      props: {
        inbox: {
          id: 1,
          provider_config: { ...baseProviderConfig },
          ...inboxOverrides,
        },
      },
    });

  beforeEach(() => {
    updateInbox = vi.fn().mockResolvedValue({});
    store = createStore({
      actions: {
        'inboxes/updateInbox': updateInbox,
      },
      getters: {
        'inboxes/getInbox': () => () => ({ provider_config: {} }),
      },
    });
  });

  it('does not discard an unsaved toggle when provider_config changes from background polling', async () => {
    const wrapper = mountPage();

    // Simulate the agent flipping a toggle without saving yet.
    wrapper.vm.state.signMsg = true;
    await wrapper.vm.$nextTick();
    expect(wrapper.vm.state.signMsg).toBe(true);

    // Simulate health polling / ActionCable pushing a runtime-only update
    // (e.g. connection_status changing while reconnecting).
    await wrapper.setProps({
      inbox: {
        id: 1,
        provider_config: {
          ...baseProviderConfig,
          connection_status: 'open',
          import_status: 'running',
        },
      },
    });

    expect(wrapper.vm.state.signMsg).toBe(true);
  });

  it('reloads the form state when switching to a different inbox', async () => {
    const wrapper = mountPage();

    wrapper.vm.state.signMsg = true;
    await wrapper.vm.$nextTick();

    await wrapper.setProps({
      inbox: {
        id: 2,
        provider_config: { ...baseProviderConfig, sign_msg: false },
      },
    });

    expect(wrapper.vm.state.signMsg).toBe(false);
  });

  it('keeps the read-only import status in sync with provider_config changes', async () => {
    const wrapper = mountPage();

    await wrapper.setProps({
      inbox: {
        id: 1,
        provider_config: {
          ...baseProviderConfig,
          import_status: 'completed',
          import_stats: { contacts_imported: 5 },
        },
      },
    });

    expect(wrapper.vm.importStatus.status).toBe('completed');
    expect(wrapper.vm.importStatus.stats.contacts_imported).toBe(5);
  });
});
