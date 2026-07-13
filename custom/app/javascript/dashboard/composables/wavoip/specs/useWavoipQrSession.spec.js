import { beforeEach, describe, expect, it, vi } from 'vitest';
import { ref } from 'vue';

const {
  connectInbox,
  getWavoipQr,
  getWavoipDeviceStatus,
  getWavoipClient,
  getWavoipClientEntry,
  getPrimaryDevice,
} = vi.hoisted(() => ({
  connectInbox: vi.fn(),
  getWavoipQr: vi.fn(),
  getWavoipDeviceStatus: vi.fn(),
  getWavoipClient: vi.fn(),
  getWavoipClientEntry: vi.fn(),
  getPrimaryDevice: vi.fn(),
}));

vi.mock('dashboard/api/inboxes', () => ({
  default: {
    getWavoipQr: (...args) => getWavoipQr(...args),
    getWavoipDeviceStatus: (...args) => getWavoipDeviceStatus(...args),
  },
}));

vi.mock('customDashboard/composables/wavoip/useWavoipConnection', () => ({
  useWavoipConnection: () => ({
    connectInbox,
  }),
}));

vi.mock('customDashboard/lib/wavoip/wavoipClientRegistry', () => ({
  getWavoipClient,
  getWavoipClientEntry,
}));

vi.mock('customDashboard/lib/wavoip/wavoipDeviceReadiness', () => ({
  getPrimaryDevice,
}));

vi.mock('customDashboard/lib/wavoip/wavoipSdkResult', () => ({
  unwrapWavoipSdkResult: raw => raw,
}));

vi.mock('customDashboard/lib/wavoip/wavoipQrImage', () => ({
  buildQrDataUrl: vi.fn(async value => `data:image/png;base64,${value}`),
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
    };

    getWavoipDeviceStatus.mockResolvedValue({
      data: { device_status: 'connecting', live: true },
    });
    getWavoipQr.mockResolvedValue({
      data: {
        device_status: 'connecting',
        qrcode_base64: 'data:image/png;base64,abc',
        live: true,
      },
    });
    connectInbox.mockResolvedValue({});
    getWavoipClient.mockReturnValue({});
    getWavoipClientEntry.mockReturnValue(undefined);
    getPrimaryDevice.mockReturnValue(device);
  });

  it('loads QR from backend on startSession and attaches SDK for live pairing', async () => {
    const onConnected = vi.fn();
    const session = useWavoipQrSession({
      inboxId: ref(9),
      phoneNumber: ref('+5511999999999'),
      onConnected,
    });

    await session.startSession();

    expect(getWavoipQr).toHaveBeenCalledTimes(1);
    expect(getWavoipQr).toHaveBeenCalledWith(9, { refresh: false });
    expect(connectInbox).toHaveBeenCalledWith(9);
    expect(device.on).toHaveBeenCalledWith('qrCodeChanged', expect.any(Function));
    expect(session.hasSdkConnection()).toBe(true);
    // SDK sync prefers the live device.qrCode when present.
    expect(session.qrDataUrl.value).toBe('data:image/png;base64,seed-qr');
    expect(session.whatsAppStatus.value).toBe('connecting');
    expect(onConnected).not.toHaveBeenCalled();
  });

  it('does not claim SDK ownership when attaching to an existing client', async () => {
    getWavoipClientEntry.mockReturnValue({ client: {}, token: 't' });
    const session = useWavoipQrSession({
      inboxId: ref(9),
      phoneNumber: ref('+5511999999999'),
    });

    await session.startSession();

    expect(connectInbox).toHaveBeenCalledWith(9);
    expect(session.hasSdkConnection()).toBe(false);
  });

  it('skips SDK connect on startSession when the device is already open', async () => {
    getWavoipQr.mockResolvedValue({
      data: { device_status: 'open', live: true },
    });
    const session = useWavoipQrSession({
      inboxId: ref(9),
      phoneNumber: ref('+5511999999999'),
    });

    await session.startSession();

    expect(connectInbox).not.toHaveBeenCalled();
    expect(session.whatsAppStatus.value).toBe('open');
  });

  it('fires onConnected when polled device status becomes open', async () => {
    vi.useFakeTimers();
    const onConnected = vi.fn();
    const session = useWavoipQrSession({
      inboxId: ref(9),
      phoneNumber: ref('+5511999999999'),
      onConnected,
    });

    await session.startSession();

    // Poll uses getWavoipDeviceStatus (force: false)
    getWavoipDeviceStatus.mockResolvedValue({
      data: { device_status: 'open', live: false },
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

  it('refreshQr requests backend restart when restart is true', async () => {
    const session = useWavoipQrSession({
      inboxId: ref(9),
      phoneNumber: ref('+5511999999999'),
    });

    await session.startSession();
    connectInbox.mockClear();
    await session.refreshQr({ restart: true });

    expect(getWavoipQr).toHaveBeenLastCalledWith(9, { refresh: true });
    expect(connectInbox).not.toHaveBeenCalled();
  });

  it('handleQrImageError clears QR and shows error state', async () => {
    const session = useWavoipQrSession({
      inboxId: ref(9),
      phoneNumber: ref('+5511999999999'),
    });

    await session.startSession();
    session.handleQrImageError();

    expect(session.qrDataUrl.value).toBe('');
    expect(session.qrRefreshError.value).toBe(true);
  });
});
