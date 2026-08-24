import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { effectScope, nextTick, ref } from 'vue';

const useAlert = vi.fn();
const dispatchMock = vi.fn();

vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({
    dispatch: (...args) => dispatchMock(...args),
    getters: {},
  }),
}));

vi.mock('dashboard/composables', () => ({
  useAlert: (...args) => useAlert(...args),
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: key => key,
  }),
}));

vi.mock(
  'customDashboard/lib/evolution_go/evolutionGoCableRegistry',
  () => ({
    subscribeEvolutionGoConnection: vi.fn(() => vi.fn()),
  })
);

import { useEvolutionGoHealthConnection } from 'customDashboard/composables/evolution_go/useEvolutionGoHealthConnection';

describe('useEvolutionGoHealthConnection', () => {
  let scope;

  beforeEach(() => {
    vi.useFakeTimers();
    vi.clearAllMocks();
    dispatchMock.mockReset();
    dispatchMock.mockRejectedValue({
      response: { status: 500, data: { error: 'network down' } },
    });
    scope?.stop();
  });

  afterEach(() => {
    scope?.stop();
    vi.useRealTimers();
  });

  it('toasts stale data only once after repeated failures', async () => {
    scope = effectScope(true);
    const inbox = ref({
      id: 42,
      provider_config: { connection_status: 'connecting' },
    });
    const { staleData } = scope.run(() =>
      useEvolutionGoHealthConnection(inbox)
    );

    await nextTick();
    await vi.advanceTimersByTimeAsync(5000);
    await vi.advanceTimersByTimeAsync(5000);

    expect(staleData.value).toBe(true);
    expect(useAlert).toHaveBeenCalledTimes(1);

    await vi.advanceTimersByTimeAsync(5000);
    expect(useAlert).toHaveBeenCalledTimes(1);
  });

  it('refreshes a single inbox without listing all inboxes', async () => {
    dispatchMock.mockImplementation(action => {
      if (action === 'inboxes/fetchEvolutionGoConnection') {
        return Promise.resolve({
          connection_status: 'open',
          phone_number: '+5511999999999',
        });
      }
      if (action === 'inboxes/fetchInboxItem') return Promise.resolve({});
      return Promise.reject(new Error(`unexpected dispatch: ${action}`));
    });

    scope = effectScope(true);
    const inbox = ref({
      id: 42,
      provider_config: { connection_status: 'connecting' },
    });
    scope.run(() => useEvolutionGoHealthConnection(inbox));
    await vi.waitFor(() => {
      expect(dispatchMock).toHaveBeenCalledWith('inboxes/fetchInboxItem', 42);
    });

    expect(dispatchMock).not.toHaveBeenCalledWith('inboxes/get', 42);
  });

  it('pauses polling after a 429 instead of retrying immediately', async () => {
    dispatchMock.mockRejectedValue({
      response: { status: 429, data: { error: 'Too Many Requests' } },
    });

    scope = effectScope(true);
    const inbox = ref({
      id: 42,
      provider_config: { connection_status: 'connecting' },
    });
    scope.run(() => useEvolutionGoHealthConnection(inbox));
    await nextTick();
    dispatchMock.mockClear();

    await vi.advanceTimersByTimeAsync(5000);
    expect(dispatchMock).not.toHaveBeenCalled();

    await vi.advanceTimersByTimeAsync(30_000);
    expect(dispatchMock).toHaveBeenCalledWith(
      'inboxes/fetchEvolutionGoConnection',
      42
    );
  });
});
