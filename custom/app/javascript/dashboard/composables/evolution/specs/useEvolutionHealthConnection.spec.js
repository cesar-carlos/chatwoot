import { beforeEach, describe, expect, it, vi, afterEach } from 'vitest';
import { effectScope, nextTick, ref } from 'vue';

const useAlert = vi.fn();
const dispatchMock = vi.fn();

vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({
    dispatch: (...args) => dispatchMock(...args),
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
  'customDashboard/composables/evolution/useEvolutionConnectionCable',
  () => ({
    useEvolutionConnectionCable: vi.fn(),
  })
);

import { useEvolutionHealthConnection } from 'customDashboard/composables/evolution/useEvolutionHealthConnection';

describe('useEvolutionHealthConnection', () => {
  let scope;

  beforeEach(() => {
    vi.useFakeTimers();
    vi.clearAllMocks();
    dispatchMock.mockReset();
    dispatchMock.mockRejectedValue({
      response: { data: { error: 'network down' } },
    });
    scope?.stop();
  });

  afterEach(() => {
    scope?.stop();
    vi.useRealTimers();
  });

  it('sets staleData after repeated connection refresh failures', async () => {
    scope = effectScope(true);
    const inbox = ref({
      id: 42,
      provider_config: { connection_status: 'connecting' },
    });
    const { staleData } = scope.run(() => useEvolutionHealthConnection(inbox));

    await nextTick();
    await vi.advanceTimersByTimeAsync(5000);
    await vi.advanceTimersByTimeAsync(5000);

    expect(staleData.value).toBe(true);
    expect(useAlert).toHaveBeenCalled();
  });

  it('shows cached connection status immediately while refreshing', async () => {
    dispatchMock.mockResolvedValue({ connection_status: 'open' });
    scope = effectScope(true);
    const inbox = ref({
      id: 42,
      provider_config: { connection_status: 'open' },
      phone_number: '+5511999999999',
    });
    const { isLoading, connectionStatus } = scope.run(() =>
      useEvolutionHealthConnection(inbox)
    );

    await nextTick();

    expect(isLoading.value).toBe(false);
    expect(connectionStatus.value).toBe('open');
  });

  it('forwards cable payloads to the QR modal when it is open', async () => {
    vi.useRealTimers();
    scope = effectScope(true);
    const inbox = ref({ id: 42 });
    const qrModalRef = ref({
      applyPayload: vi.fn(),
    });
    const { isQrModalOpen, applyPayload } = scope.run(() =>
      useEvolutionHealthConnection(inbox, { qrModalRef })
    );

    isQrModalOpen.value = true;
    await applyPayload({
      connection_status: 'connecting',
      qrcode_base64: 'data:image/png;base64,abc',
    });

    expect(qrModalRef.value.applyPayload).toHaveBeenCalledWith({
      connection_status: 'connecting',
      qrcode_base64: 'data:image/png;base64,abc',
    });
  });

  it('does not open the QR modal when restart fails', async () => {
    scope = effectScope(true);
    const inbox = ref({ id: 42 });
    const { restart, isQrModalOpen } = scope.run(() =>
      useEvolutionHealthConnection(inbox)
    );
    await nextTick();

    const confirmDialog = { showConfirmation: vi.fn().mockResolvedValue(true) };
    await restart(confirmDialog);

    expect(isQrModalOpen.value).toBe(false);
    expect(useAlert).toHaveBeenCalled();
  });

  it('resolves inbox id from a getter function ref', async () => {
    dispatchMock.mockResolvedValue({ connection_status: 'open' });
    scope = effectScope(true);
    const inbox = {
      id: 99,
      provider_config: { connection_status: 'open' },
    };
    const { connectionStatus } = scope.run(() =>
      useEvolutionHealthConnection(() => inbox)
    );

    await nextTick();

    expect(connectionStatus.value).toBe('open');
    expect(dispatchMock).toHaveBeenCalledWith(
      'inboxes/fetchEvolutionConnection',
      99
    );
  });

  it('opens the QR modal after a successful restart', async () => {
    scope = effectScope(true);
    dispatchMock.mockImplementation(action => {
      if (action === 'inboxes/evolutionRestart') {
        return Promise.resolve({ connection_status: 'connecting' });
      }
      if (action === 'inboxes/get') return Promise.resolve({});
      return Promise.reject(
        new Error(`unexpected dispatch in test: ${action}`)
      );
    });
    const inbox = ref({ id: 42 });
    const { restart, isQrModalOpen } = scope.run(() =>
      useEvolutionHealthConnection(inbox)
    );
    await nextTick();

    const confirmDialog = { showConfirmation: vi.fn().mockResolvedValue(true) };
    await restart(confirmDialog);

    expect(isQrModalOpen.value).toBe(true);
  });
});
