import { describe, expect, it, vi, beforeEach, afterEach } from 'vitest';
import { useEvolutionQrSession } from 'customDashboard/composables/evolution/useEvolutionQrSession';

function createStore() {
  return {
    dispatch: vi.fn().mockResolvedValue({
      connection_status: 'connecting',
      qrcode_base64: '',
    }),
  };
}

describe('useEvolutionQrSession', () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it('does not set qrRefreshError while connecting without QR', async () => {
    const store = createStore();
    const { connectionStatus, qrRefreshError, startSession, stopSession } =
      useEvolutionQrSession({
        inboxId: 1,
        store,
      });

    await startSession();
    expect(connectionStatus.value).toBe('connecting');
    expect(qrRefreshError.value).toBe(false);

    stopSession();
  });

  it('deduplicates overlapping refreshConnection calls', async () => {
    let resolveFirst;
    const store = {
      dispatch: vi.fn().mockImplementation(
        () =>
          new Promise(resolve => {
            resolveFirst = resolve;
          })
      ),
    };
    const { refreshConnection, stopSession } = useEvolutionQrSession({
      inboxId: 1,
      store,
    });

    const first = refreshConnection();
    const second = refreshConnection();

    expect(store.dispatch).toHaveBeenCalledTimes(1);

    resolveFirst?.({ connection_status: 'connecting' });
    await first;
    await second;
    stopSession();
  });

  it('stops polling and calls onConnected when status becomes open', async () => {
    const store = createStore();
    store.dispatch.mockResolvedValue({
      connection_status: 'open',
      phone_number: '+5511999999999',
    });
    const onConnected = vi.fn();
    const { startSession, stopSession } = useEvolutionQrSession({
      inboxId: 1,
      store,
      onConnected,
    });

    await startSession();
    expect(onConnected).toHaveBeenCalledTimes(1);
    stopSession();
  });
});
