import { describe, expect, it, vi, beforeEach, afterEach } from 'vitest';
import { useEvolutionGoQrSession } from 'customDashboard/composables/evolution_go/useEvolutionGoQrSession';

function createStore() {
  return {
    dispatch: vi.fn().mockResolvedValue({
      connection_status: 'connecting',
      qrcode_base64: '',
    }),
  };
}

describe('useEvolutionGoQrSession', () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it('does not set qrRefreshError while connecting without QR', async () => {
    const store = createStore();
    const { connectionStatus, qrRefreshError, startSession, stopSession } =
      useEvolutionGoQrSession({
        inboxId: 1,
        store,
      });

    await startSession();
    expect(connectionStatus.value).toBe('connecting');
    expect(qrRefreshError.value).toBe(false);

    stopSession();
  });

  it('requests a fresh QR on expiry instead of polling GET only', async () => {
    const store = createStore();
    store.dispatch.mockResolvedValue({
      connection_status: 'connecting',
      qrcode_base64: 'data:image/png;base64,abc',
    });

    const { startSession, stopSession } = useEvolutionGoQrSession({
      inboxId: 1,
      store,
    });

    await startSession();
    store.dispatch.mockClear();

    vi.advanceTimersByTime(45_000);
    await Promise.resolve();

    expect(store.dispatch).toHaveBeenCalledWith(
      'inboxes/evolutionGoReconnect',
      1
    );
    stopSession();
  });
});
