import { beforeEach, describe, expect, it, vi } from 'vitest';
import { flushPromises, mount } from '@vue/test-utils';
import { createStore } from 'vuex';

const {
  registerWavoipCallSession,
  syncWithAvailability,
  cleanupSession,
  useWavoipCallSession,
  requestWavoipNotificationPermission,
} = vi.hoisted(() => ({
  registerWavoipCallSession: vi.fn(),
  syncWithAvailability: vi.fn(),
  cleanupSession: vi.fn(),
  useWavoipCallSession: vi.fn(),
  requestWavoipNotificationPermission: vi.fn(),
}));

vi.mock('customDashboard/lib/voice/voiceSessionRegistry', () => ({
  registerWavoipCallSession,
}));

vi.mock('customDashboard/composables/wavoip/useWavoipCallSession', () => ({
  useWavoipCallSession,
}));

vi.mock('customDashboard/composables/wavoip/useWavoipActiveCall', () => ({
  endActiveCall: vi.fn().mockResolvedValue(undefined),
}));

vi.mock('customDashboard/composables/wavoip/useWavoipNotifications', () => ({
  requestWavoipNotificationPermission,
}));

vi.mock('customDashboard/lib/wavoip/wavoipNotificationEnvironment', () => ({
  isIosSafariWithoutPwa: () => false,
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

import WavoipConnectionHost from '../WavoipConnectionHost.vue';

describe('WavoipConnectionHost', () => {
  const store = createStore({
    getters: {
      getInboxes: () => [],
    },
  });

  beforeEach(() => {
    vi.clearAllMocks();
    useWavoipCallSession.mockReturnValue({
      syncWithAvailability,
      cleanupSession,
    });
  });

  it('registers the Wavoip session singleton during setup', () => {
    const session = { syncWithAvailability, cleanupSession };
    useWavoipCallSession.mockReturnValue(session);

    mount(WavoipConnectionHost, {
      global: { plugins: [store] },
    });

    expect(useWavoipCallSession).toHaveBeenCalledTimes(1);
    expect(registerWavoipCallSession).toHaveBeenCalledWith(session);
  });

  it('does not request notification permission during setup', async () => {
    mount(WavoipConnectionHost, {
      global: { plugins: [store] },
    });

    await flushPromises();

    expect(requestWavoipNotificationPermission).not.toHaveBeenCalled();
  });

  it('clears the singleton on unmount', async () => {
    const wrapper = mount(WavoipConnectionHost, {
      global: { plugins: [store] },
    });

    wrapper.unmount();
    await flushPromises();

    expect(registerWavoipCallSession).toHaveBeenLastCalledWith(null);
    expect(cleanupSession).toHaveBeenCalledTimes(1);
  });
});
