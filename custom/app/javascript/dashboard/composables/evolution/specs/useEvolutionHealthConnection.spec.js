import { beforeEach, describe, expect, it, vi, afterEach } from 'vitest';
import { effectScope, nextTick, ref } from 'vue';

const useAlert = vi.fn();

vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({
    dispatch: vi
      .fn()
      .mockRejectedValue({ response: { data: { error: 'network down' } } }),
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
    scope?.stop();
  });

  afterEach(() => {
    scope?.stop();
    vi.useRealTimers();
  });

  it('sets staleData after repeated connection refresh failures', async () => {
    scope = effectScope(true);
    const inbox = ref({ id: 42 });
    const { staleData } = scope.run(() => useEvolutionHealthConnection(inbox));

    await nextTick();
    await vi.advanceTimersByTimeAsync(5000);
    await vi.advanceTimersByTimeAsync(5000);

    expect(staleData.value).toBe(true);
    expect(useAlert).toHaveBeenCalled();
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
});
