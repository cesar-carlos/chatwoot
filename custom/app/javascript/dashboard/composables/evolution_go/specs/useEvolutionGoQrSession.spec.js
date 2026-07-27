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

  it('clears pairing code when a new QR payload arrives', () => {
    const store = createStore();
    const { pairingCode, applyPayload, stopSession } = useEvolutionGoQrSession({
      inboxId: 1,
      store,
    });

    applyPayload({
      connection_status: 'connecting',
      pairing_code: 'ABCD-1234',
    });
    expect(pairingCode.value).toBe('ABCD-1234');

    applyPayload({
      connection_status: 'connecting',
      qrcode_base64: 'data:image/png;base64,abc',
    });
    expect(pairingCode.value).toBe('');
    stopSession();
  });

  it('does not start polling after stopSession during startSession', async () => {
    let resolveRefresh;
    const store = {
      dispatch: vi.fn(
        () =>
          new Promise(resolve => {
            resolveRefresh = resolve;
          })
      ),
    };

    const { startSession, stopSession } = useEvolutionGoQrSession({
      inboxId: 1,
      store,
    });

    const pending = startSession();
    stopSession();
    resolveRefresh({
      connection_status: 'connecting',
      qrcode_base64: 'data:image/png;base64,abc',
    });
    await pending;

    store.dispatch.mockClear();
    vi.advanceTimersByTime(10_000);
    await Promise.resolve();

    expect(store.dispatch).not.toHaveBeenCalled();
  });
});
