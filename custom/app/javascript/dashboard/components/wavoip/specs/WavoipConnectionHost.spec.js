import { beforeEach, describe, expect, it, vi } from 'vitest';
import { ref } from 'vue';
import { mount } from '@vue/test-utils';
import { createStore } from 'vuex';

const {
  registerWavoipCallSession,
  syncWithAvailability,
  cleanupSession,
  useWavoipCallSession,
} = vi.hoisted(() => ({
  registerWavoipCallSession: vi.fn(),
  syncWithAvailability: vi.fn(),
  cleanupSession: vi.fn(),
  useWavoipCallSession: vi.fn(),
}));

vi.mock('customDashboard/lib/voice/voiceSessionRegistry', () => ({
  registerWavoipCallSession,
}));

vi.mock('customDashboard/composables/wavoip/useWavoipCallSession', () => ({
  useWavoipCallSession,
}));

vi.mock('customDashboard/composables/wavoip/useWavoipNotifications', () => ({
  requestWavoipNotificationPermission: vi.fn().mockResolvedValue('granted'),
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

  it('clears the singleton on unmount', () => {
    const wrapper = mount(WavoipConnectionHost, {
      global: { plugins: [store] },
    });

    wrapper.unmount();

    expect(registerWavoipCallSession).toHaveBeenLastCalledWith(null);
    expect(cleanupSession).toHaveBeenCalledTimes(1);
  });
});
