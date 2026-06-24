import { beforeEach, describe, expect, it, vi } from 'vitest';
import { ref } from 'vue';

const {
  connectInbox,
  wakeUpInboxDevice,
  getWavoipSdkBootstrap,
  getWavoipInboxShow,
  getWavoipClient,
  getPrimaryDevice,
} = vi.hoisted(() => ({
  connectInbox: vi.fn(),
  wakeUpInboxDevice: vi.fn(),
  getWavoipSdkBootstrap: vi.fn(),
  getWavoipInboxShow: vi.fn(),
  getWavoipClient: vi.fn(),
  getPrimaryDevice: vi.fn(),
}));

vi.mock('dashboard/api/inboxes', () => ({
  default: {
    getWavoipSdkBootstrap: (...args) => getWavoipSdkBootstrap(...args),
    show: (...args) => getWavoipInboxShow(...args),
  },
}));

vi.mock('customDashboard/composables/wavoip/useWavoipConnection', () => ({
  useWavoipConnection: () => ({
    connectInbox,
    wakeUpInboxDevice,
  }),
}));

vi.mock('customDashboard/lib/wavoip/wavoipClientRegistry', () => ({
  getWavoipClient,
}));

vi.mock('customDashboard/lib/wavoip/wavoipDeviceReadiness', () => ({
  getPrimaryDevice,
}));

vi.mock('customDashboard/lib/wavoip/wavoipSdkResult', () => ({
  unwrapWavoipSdkResult: raw => raw,
}));

vi.mock('customDashboard/lib/wavoip/wavoipQrImage', () => ({
  buildQrDataUrl: vi.fn(async value => `data:image/png;base64,${value}`),
  buildWavoipQrImageUrl: vi.fn(
    token => `https://devices.wavoip.com/${token}/qr`
  ),
  withCacheBust: vi.fn(url => `${url}?t=1`),
}));

import { useWavoipQrSession } from 'customDashboard/composables/wavoip/useWavoipQrSession';

describe('useWavoipQrSession', () => {
  let device;
  let handlers;

  beforeEach(() => {
    vi.clearAllMocks();
    handlers = {};

    device = {
      status: 'connecting',
      qrCode: 'seed-qr',
      on: vi.fn((event, handler) => {
        handlers[event] = handler;
        return () => {
          delete handlers[event];
        };
      }),
      pairingCode: vi.fn(async () => ({ pairingCode: '1234-5678', err: null })),
      restart: vi.fn(async () => {}),
    };

    getWavoipSdkBootstrap.mockResolvedValue({
      data: { device_token: 'tok_1' },
    });
    getWavoipInboxShow.mockResolvedValue({
      data: { provider_config: { device_status: 'connecting' } },
    });
    connectInbox.mockResolvedValue({});
    getWavoipClient.mockReturnValue({});
    getPrimaryDevice.mockReturnValue(device);
  });

  it('loads fallback QR image on startSession without SDK connect', async () => {
    const onConnected = vi.fn();
    const session = useWavoipQrSession({
      inboxId: ref(9),
      phoneNumber: ref('+5511999999999'),
      onConnected,
    });

    await session.startSession();

    expect(connectInbox).not.toHaveBeenCalled();
    expect(session.qrDataUrl.value).toBe(
      'https://devices.wavoip.com/tok_1/qr?t=1'
    );
    expect(session.whatsAppStatus.value).toBe('connecting');
    expect(onConnected).not.toHaveBeenCalled();
  });

  it('fires onConnected when polled inbox status becomes open', async () => {
    vi.useFakeTimers();
    const onConnected = vi.fn();
    const session = useWavoipQrSession({
      inboxId: ref(9),
      phoneNumber: ref('+5511999999999'),
      onConnected,
    });

    await session.startSession();
    getWavoipInboxShow.mockResolvedValue({
      data: { provider_config: { device_status: 'open' } },
    });

    await vi.advanceTimersByTimeAsync(4000);

    expect(onConnected).toHaveBeenCalledTimes(1);
    expect(session.qrDataUrl.value).toBe('');
    vi.useRealTimers();
  });

  it('updates QR when qrCodeChanged fires after SDK connect', async () => {
    const session = useWavoipQrSession({
      inboxId: ref(9),
      phoneNumber: ref('+5511999999999'),
    });

    await session.startSession();
    await session.requestPairingCode();
    await handlers.qrCodeChanged('next-qr');

    expect(session.qrDataUrl.value).toBe('data:image/png;base64,next-qr');
  });

  it('stopSession removes device listeners', async () => {
    const session = useWavoipQrSession({
      inboxId: ref(9),
      phoneNumber: ref('+5511999999999'),
    });

    await session.startSession();
    await session.requestPairingCode();
    session.stopSession();

    expect(handlers.qrCodeChanged).toBeUndefined();
    expect(handlers.statusChanged).toBeUndefined();
  });

  it('requestPairingCode connects SDK and stores the pairing code', async () => {
    const session = useWavoipQrSession({
      inboxId: ref(9),
      phoneNumber: ref('+5511999999999'),
    });

    await session.startSession();
    await session.requestPairingCode();

    expect(connectInbox).toHaveBeenCalledWith(9);
    expect(device.pairingCode).toHaveBeenCalledWith('+5511999999999');
    expect(session.pairingCode.value).toBe('1234-5678');
  });
});
