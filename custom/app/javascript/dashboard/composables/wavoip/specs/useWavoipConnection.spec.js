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
}));

vi.mock('vuex', () => ({
  useStore: () => ({
    getters: {
      'inboxes/getInboxes': [
        { id: 21, channel_type: INBOX_TYPES.WAVOIP },
        { id: 22, channel_type: 'Channel::Whatsapp' },
      ],
    },
  }),
}));

import { useWavoipConnection } from '../useWavoipConnection';

const createOpenDeviceClient = () => ({
  getDevices: () => [{ status: 'open', on: vi.fn() }],
});

describe('useWavoipConnection', () => {
  beforeEach(() => {
    getWavoipSdkBootstrap.mockReset();
    connectWavoipInbox.mockReset();
    disconnectWavoipInbox.mockReset();
    teardownAllWavoipClients.mockReset();
    getWavoipClient.mockReset();
  });

  it('connects an inbox using the bootstrap device token', async () => {
    const client = createOpenDeviceClient();
    getWavoipSdkBootstrap.mockResolvedValue({ data: { device_token: 'token-abc' } });
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

  it('syncs connections for assigned Wavoip inboxes when online', async () => {
    const client = createOpenDeviceClient();
    getWavoipSdkBootstrap.mockResolvedValue({ data: { device_token: 'token-sync' } });
    connectWavoipInbox.mockResolvedValue(client);
    getWavoipClient.mockReturnValue(null);

    const { syncConnections } = useWavoipConnection();
    await syncConnections('online');

    expect(connectWavoipInbox).toHaveBeenCalledWith(21, 'token-sync');
    expect(connectWavoipInbox).not.toHaveBeenCalledWith(22, expect.anything());
  });

  it('tears down clients when availability is offline', async () => {
    const { syncConnections } = useWavoipConnection();
    await syncConnections('offline');

    expect(teardownAllWavoipClients).toHaveBeenCalled();
  });
});
