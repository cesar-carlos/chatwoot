import { beforeEach, describe, expect, it, vi } from 'vitest';
import { ref } from 'vue';

const {
  connectInbox,
  wakeUpInboxDevice,
  getWavoipSdkBootstrap,
  getWavoipClient,
  getPrimaryDevice,
} = vi.hoisted(() => ({
  connectInbox: vi.fn(),
  wakeUpInboxDevice: vi.fn(),
  getWavoipSdkBootstrap: vi.fn(),
  getWavoipClient: vi.fn(),
  getPrimaryDevice: vi.fn(),
}));

vi.mock('dashboard/api/inboxes', () => ({
  default: {
    getWavoipSdkBootstrap: (...args) => getWavoipSdkBootstrap(...args),
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
  unwrapWavoipSdkResult: (raw, key) => raw,
}));

vi.mock('customDashboard/lib/wavoip/wavoipQrImage', () => ({
  buildQrDataUrl: vi.fn(async value => `data:image/png;base64,${value}`),
  buildWavoipQrImageUrl: vi.fn(token => `https://devices.wavoip.com/${token}/qr`),
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

    getWavoipSdkBootstrap.mockResolvedValue({ data: { device_token: 'tok_1' } });
    connectInbox.mockResolvedValue({});
    getWavoipClient.mockReturnValue({});
    getPrimaryDevice.mockReturnValue(device);
  });

  it('loads QR data URL from the device seed on startSession', async () => {
    const onConnected = vi.fn();
    const session = useWavoipQrSession({
      inboxId: ref(9),
      phoneNumber: ref('+5511999999999'),
      onConnected,
    });

    await session.startSession();

    expect(connectInbox).toHaveBeenCalledWith(9);
    expect(session.qrDataUrl.value).toBe('data:image/png;base64,seed-qr');
    expect(session.whatsAppStatus.value).toBe('connecting');
    expect(onConnected).not.toHaveBeenCalled();
  });

  it('fires onConnected when status becomes open', async () => {
    const onConnected = vi.fn();
    const session = useWavoipQrSession({
      inboxId: ref(9),
      phoneNumber: ref('+5511999999999'),
      onConnected,
    });

    await session.startSession();
    handlers.statusChanged('open');

    expect(onConnected).toHaveBeenCalledTimes(1);
    expect(session.qrDataUrl.value).toBe('');
  });

  it('updates QR when qrCodeChanged fires', async () => {
    const session = useWavoipQrSession({
      inboxId: ref(9),
      phoneNumber: ref('+5511999999999'),
    });

    await session.startSession();
    await handlers.qrCodeChanged('next-qr');

    expect(session.qrDataUrl.value).toBe('data:image/png;base64,next-qr');
  });

  it('stopSession removes device listeners', async () => {
    const session = useWavoipQrSession({
      inboxId: ref(9),
      phoneNumber: ref('+5511999999999'),
    });

    await session.startSession();
    session.stopSession();

    expect(handlers.qrCodeChanged).toBeUndefined();
    expect(handlers.statusChanged).toBeUndefined();
  });

  it('requestPairingCode stores the SDK pairing code', async () => {
    const session = useWavoipQrSession({
      inboxId: ref(9),
      phoneNumber: ref('+5511999999999'),
    });

    await session.startSession();
    await session.requestPairingCode();

    expect(device.pairingCode).toHaveBeenCalledWith('+5511999999999');
    expect(session.pairingCode.value).toBe('1234-5678');
  });
});
