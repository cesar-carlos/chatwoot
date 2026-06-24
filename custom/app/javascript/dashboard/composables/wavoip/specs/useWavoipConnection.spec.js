import { beforeEach, describe, expect, it, vi } from 'vitest';
import { INBOX_TYPES } from 'dashboard/helper/inbox';

const getWavoipSdkBootstrap = vi.fn();
const connectWavoipInbox = vi.fn();
const disconnectWavoipInbox = vi.fn();
const teardownAllWavoipClients = vi.fn();
const getWavoipClient = vi.fn();

vi.mock('dashboard/api/inboxes', () => ({
  default: {
    getWavoipSdkBootstrap: (...args) => getWavoipSdkBootstrap(...args),
  },
}));

vi.mock('customDashboard/lib/wavoip/wavoipClientRegistry', () => ({
  connectWavoipInbox: (...args) => connectWavoipInbox(...args),
  disconnectWavoipInbox: (...args) => disconnectWavoipInbox(...args),
  teardownAllWavoipClients: (...args) => teardownAllWavoipClients(...args),
  getWavoipClient: (...args) => getWavoipClient(...args),
  registerDeviceUnsubscriber: vi.fn(),
}));

const setWavoipConnectionStatus = vi.fn();
const setWavoipWhatsAppStatus = vi.fn();
const setWavoipRestricted = vi.fn();
const clearWavoipDeviceStatus = vi.fn();

vi.mock('customDashboard/lib/wavoip/wavoipDeviceStatus', () => ({
  setWavoipConnectionStatus: (...args) => setWavoipConnectionStatus(...args),
  setWavoipWhatsAppStatus: (...args) => setWavoipWhatsAppStatus(...args),
  setWavoipRestricted: (...args) => setWavoipRestricted(...args),
  clearWavoipDeviceStatus: (...args) => clearWavoipDeviceStatus(...args),
}));

vi.mock('customDashboard/lib/wavoip/wavoipDiagnosticsCollector', () => ({
  recordConnectivityIssue: vi.fn(),
}));

vi.mock('vuex', () => ({
  useStore: () => ({
    getters: {
      'inboxes/getInboxes': [
        {
          id: 21,
          channel_type: INBOX_TYPES.WAVOIP,
          current_user_inbox_member: true,
          provider_config: { device_status: 'open' },
        },
        { id: 22, channel_type: 'Channel::Whatsapp' },
        {
          id: 23,
          channel_type: INBOX_TYPES.WAVOIP,
          current_user_inbox_member: true,
          provider_config: { device_status: 'close' },
        },
      ],
      getCurrentRole: 'agent',
    },
  }),
}));

import { useWavoipConnection } from '../useWavoipConnection';

let connectionStatusHandler;

const createOpenDeviceClient = () => ({
  getDevices: () => [
    {
      status: 'open',
      connectionStatus: 'connected',
      restricted: false,
      on: (event, handler) => {
        if (event === 'connectionStatusChanged') {
          connectionStatusHandler = handler;
        }
        return () => {};
      },
    },
  ],
});

describe('useWavoipConnection', () => {
  beforeEach(() => {
    connectionStatusHandler = undefined;
    setWavoipConnectionStatus.mockReset();
    setWavoipWhatsAppStatus.mockReset();
    setWavoipRestricted.mockReset();
    clearWavoipDeviceStatus.mockReset();
    getWavoipSdkBootstrap.mockReset();
    connectWavoipInbox.mockReset();
    disconnectWavoipInbox.mockReset();
    teardownAllWavoipClients.mockReset();
    getWavoipClient.mockReset();
  });

  it('connects an inbox using the bootstrap device token', async () => {
    const client = createOpenDeviceClient();
    getWavoipSdkBootstrap.mockResolvedValue({
      data: { device_token: 'token-abc' },
    });
    connectWavoipInbox.mockResolvedValue(client);
    getWavoipClient.mockReturnValue(null);

    const { connectForInbox } = useWavoipConnection();
    const result = await connectForInbox(11);

    expect(getWavoipSdkBootstrap).toHaveBeenCalledWith(11);
    expect(connectWavoipInbox).toHaveBeenCalledWith(11, 'token-abc');
    expect(result).toBe(client);
  });

  it('returns null when bootstrap has no device token', async () => {
    getWavoipSdkBootstrap.mockResolvedValue({ data: {} });
    getWavoipClient.mockReturnValue(null);

    const { connectForInbox } = useWavoipConnection();
    const result = await connectForInbox(12);

    expect(result).toBeNull();
    expect(connectWavoipInbox).not.toHaveBeenCalled();
  });

  it('syncs connections only for open Wavoip inboxes when online', async () => {
    const client = createOpenDeviceClient();
    getWavoipSdkBootstrap.mockResolvedValue({
      data: { device_token: 'token-sync' },
    });
    connectWavoipInbox.mockResolvedValue(client);
    getWavoipClient.mockReturnValue(null);

    const { syncConnections } = useWavoipConnection();
    await syncConnections('online');

    expect(connectWavoipInbox).toHaveBeenCalledWith(21, 'token-sync');
    expect(connectWavoipInbox).not.toHaveBeenCalledWith(22, expect.anything());
    expect(connectWavoipInbox).not.toHaveBeenCalledWith(23, expect.anything());
  });

  it('tears down clients when availability is offline', async () => {
    const { syncConnections } = useWavoipConnection();
    await syncConnections('offline');

    expect(teardownAllWavoipClients).toHaveBeenCalled();
  });

  it('forwards connectionStatusChanged to device status store', async () => {
    const client = createOpenDeviceClient();
    getWavoipSdkBootstrap.mockResolvedValue({
      data: { device_token: 'token-conn' },
    });
    connectWavoipInbox.mockResolvedValue(client);
    getWavoipClient.mockReturnValue(null);

    const { connectForInbox } = useWavoipConnection();
    await connectForInbox(31);

    expect(setWavoipConnectionStatus).toHaveBeenCalledWith(31, 'connected');
    connectionStatusHandler?.('reconnecting');
    expect(setWavoipConnectionStatus).toHaveBeenCalledWith(31, 'reconnecting');
  });
});
