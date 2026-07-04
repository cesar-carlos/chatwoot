import { describe, expect, it, vi, beforeEach } from 'vitest';
import { shallowMount } from '@vue/test-utils';
import { ref } from 'vue';

const qrSessionState = {
  connectionStatus: ref('connecting'),
  qrcodeBase64: ref(''),
  pairingCode: ref(''),
  isLoading: ref(false),
  isRefreshing: ref(false),
  qrRefreshError: ref(false),
  requestNewQr: vi.fn(),
  startSession: vi.fn(),
  stopSession: vi.fn(),
  applyPayload: vi.fn(),
};

vi.mock('dashboard/composables', () => ({
  useAlert: vi.fn(),
}));

vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch: vi.fn() }),
}));

vi.mock('customDashboard/composables/evolution/useEvolutionQrSession', () => ({
  useEvolutionQrSession: () => qrSessionState,
}));

vi.mock(
  'customDashboard/composables/evolution/useEvolutionConnectionCable',
  () => ({
    subscribeEvolutionConnection: vi.fn(() => vi.fn()),
  })
);

import EvolutionQrScanModal from '../EvolutionQrScanModal.vue';

describe('EvolutionQrScanModal', () => {
  const mountModal = (props = {}) =>
    shallowMount(EvolutionQrScanModal, {
      global: {
        mocks: { $t: key => key },
        stubs: {
          Dialog: { template: '<div><slot /><slot name="footer" /></div>' },
          Button: true,
          Spinner: true,
        },
      },
      props: { inboxId: 1, ...props },
    });

  beforeEach(() => {
    qrSessionState.connectionStatus.value = 'connecting';
    qrSessionState.qrcodeBase64.value = '';
    qrSessionState.pairingCode.value = '';
    qrSessionState.isLoading.value = false;
    qrSessionState.isRefreshing.value = false;
    qrSessionState.qrRefreshError.value = false;
  });

  it('shows the loading state (not an error) when the connection is merely "close" without an explicit refresh error', () => {
    qrSessionState.connectionStatus.value = 'close';
    qrSessionState.qrRefreshError.value = false;

    const wrapper = mountModal();

    expect(wrapper.vm.showLoading).toBe(true);
    expect(wrapper.vm.showQrError).toBe(false);
  });

  it('shows the error state when a refresh actually fails', () => {
    qrSessionState.connectionStatus.value = 'close';
    qrSessionState.qrRefreshError.value = true;

    const wrapper = mountModal();

    expect(wrapper.vm.showLoading).toBe(false);
    expect(wrapper.vm.showQrError).toBe(true);
  });

  it('prioritizes showing the QR code once available even if status briefly reads close', () => {
    qrSessionState.connectionStatus.value = 'close';
    qrSessionState.qrcodeBase64.value = 'data:image/png;base64,abc';

    const wrapper = mountModal();

    expect(wrapper.vm.showQr).toBe(true);
    expect(wrapper.vm.showLoading).toBe(false);
    expect(wrapper.vm.showQrError).toBe(false);
  });
});
