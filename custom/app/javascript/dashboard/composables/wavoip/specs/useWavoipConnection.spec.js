import { beforeEach, describe, expect, it, vi } from 'vitest';
import { INBOX_TYPES } from 'dashboard/helper/inbox';

const getWavoipSdkBootstrap = vi.fn();
const connectWavoipInbox = vi.fn();
const disconnectWavoipInbox = vi.fn();
const teardownAllWavoipClients = vi.fn();
const getWavoipClient = vi.fn();
const getWavoipClientEntry = vi.fn();

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
  getWavoipClientEntry: (...args) => getWavoipClientEntry(...args),
  registerDeviceUnsubscriber: vi.fn(),
}));

const setWavoipConnectionStatus = vi.fn();
const setWavoipWhatsAppStatus = vi.fn();
const setWavoipRestricted = vi.fn();
const setWavoipActiveCalls = vi.fn();
const setWavoipNumChannels = vi.fn();
const clearWavoipDeviceStatus = vi.fn();

const { connectionStatusByInbox, connectionStatusRefs } = vi.hoisted(() => ({
  connectionStatusByInbox: new Map(),
  connectionStatusRefs: new Map(),
}));

vi.mock('customDashboard/lib/wavoip/wavoipDeviceStatus', async () => {
  const { ref } = await import('vue');
  const ensureRef = inboxId => {
    if (!connectionStatusRefs.has(inboxId)) {
      connectionStatusRefs.set(inboxId, ref(null));
    }
    return connectionStatusRefs.get(inboxId);
  };

  return {
    getWavoipDeviceStatus: inboxId => ({
      connectionStatus: ensureRef(inboxId),
    }),
    setWavoipConnectionStatus: (...args) => {
      const [inboxId, status] = args;
      connectionStatusByInbox.set(inboxId, status);
      ensureRef(inboxId).value = status;
      return setWavoipConnectionStatus(...args);
    },
    setWavoipWhatsAppStatus: (...args) => setWavoipWhatsAppStatus(...args),
    setWavoipRestricted: (...args) => setWavoipRestricted(...args),
    setWavoipActiveCalls: (...args) => setWavoipActiveCalls(...args),
    setWavoipNumChannels: (...args) => setWavoipNumChannels(...args),
    clearWavoipDeviceStatus: (...args) => {
      const [inboxId] = args;
      connectionStatusByInbox.delete(inboxId);
      connectionStatusRefs.delete(inboxId);
      return clearWavoipDeviceStatus(...args);
    },
    isWavoipWebSocketDisconnected: inboxId =>
      connectionStatusByInbox.get(inboxId) === 'disconnected',
    isWavoipWebSocketReady: inboxId => {
      const status = connectionStatusByInbox.get(inboxId);
      return status === 'connected' || status == null;
    },
  };
});

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
  createStore: vi.fn(() => ({
    getters: {},
    dispatch: vi.fn(),
    commit: vi.fn(),
  })),
}));

let useWavoipConnection;
let getWavoipSdkSyncKey;
let ensureDeviceReadiness;
let BOOTSTRAP_CACHE_TTL_MS;
let connectionStatusHandler;

let activeCallsChangedHandler;

const createOpenDeviceClient = () => ({
  getDevices: () => [
    {
      status: 'open',
      connectionStatus: 'connected',
      restricted: false,
      activeCalls: 1,
      num_channels: 3,
      on: (event, handler) => {
        if (event === 'connectionStatusChanged') {
          connectionStatusHandler = handler;
        }
        if (event === 'activeCallsChanged') {
          activeCallsChangedHandler = handler;
        }
        return () => {};
      },
    },
  ],
});

describe('useWavoipConnection', () => {
  beforeEach(async () => {
    vi.resetModules();
    ({
      useWavoipConnection,
      getWavoipSdkSyncKey,
      ensureDeviceReadiness,
      BOOTSTRAP_CACHE_TTL_MS,
    } = await import('../useWavoipConnection'));
    connectionStatusHandler = undefined;
    activeCallsChangedHandler = undefined;
    connectionStatusByInbox.clear();
    connectionStatusRefs.clear();
    setWavoipConnectionStatus.mockReset();
    setWavoipWhatsAppStatus.mockReset();
    setWavoipRestricted.mockReset();
    setWavoipActiveCalls.mockReset();
    clearWavoipDeviceStatus.mockReset();
    getWavoipSdkBootstrap.mockReset();
    connectWavoipInbox.mockReset();
    disconnectWavoipInbox.mockReset();
    teardownAllWavoipClients.mockReset();
    getWavoipClient.mockReset();
    getWavoipClientEntry.mockReset();
  }, 30_000);

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

  it('passes ICE servers from bootstrap into the SDK connect', async () => {
    const client = createOpenDeviceClient();
    getWavoipSdkBootstrap.mockResolvedValue({
      data: {
        device_token: 'token-ice',
        ice_servers: [{ urls: ['stun:stun.l.google.com:19302'] }],
      },
    });
    connectWavoipInbox.mockResolvedValue(client);
    getWavoipClient.mockReturnValue(null);

    const { connectForInbox } = useWavoipConnection();
    await connectForInbox(41);

    expect(connectWavoipInbox).toHaveBeenCalledWith(41, 'token-ice', {
      iceConfig: {
        iceServers: [{ urls: ['stun:stun.l.google.com:19302'] }],
      },
    });
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

  it('forwards activeCallsChanged to device status store', async () => {
    const client = createOpenDeviceClient();
    getWavoipSdkBootstrap.mockResolvedValue({
      data: { device_token: 'token-active' },
    });
    connectWavoipInbox.mockResolvedValue(client);
    getWavoipClient.mockReturnValue(null);

    const { connectForInbox } = useWavoipConnection();
    await connectForInbox(32);

    expect(setWavoipActiveCalls).toHaveBeenCalledWith(32, 1);
    activeCallsChangedHandler?.(2);
    expect(setWavoipActiveCalls).toHaveBeenCalledWith(32, 2);
  });

  it('reconnects when bootstrap token changes for an already-connected inbox', async () => {
    const client = createOpenDeviceClient();
    getWavoipSdkBootstrap
      .mockResolvedValueOnce({ data: { device_token: 'token-a' } })
      .mockResolvedValueOnce({ data: { device_token: 'token-b' } });
    connectWavoipInbox.mockResolvedValue(client);
    getWavoipClient.mockReturnValue(null);
    getWavoipClientEntry.mockReturnValue({
      client,
      token: 'token-a',
    });

    const { connectForInbox, syncConnections } = useWavoipConnection();
    await connectForInbox(21);

    expect(connectWavoipInbox).toHaveBeenCalledWith(21, 'token-a');

    const now = Date.now();
    const nowSpy = vi
      .spyOn(Date, 'now')
      .mockReturnValue(now + BOOTSTRAP_CACHE_TTL_MS + 1);

    try {
      await syncConnections('online');

      expect(disconnectWavoipInbox).toHaveBeenCalledWith(21);
      expect(connectWavoipInbox).toHaveBeenCalledWith(21, 'token-b');
    } finally {
      nowSpy.mockRestore();
    }
  });

  it('does not refetch bootstrap on sync while the cache TTL is valid', async () => {
    const client = createOpenDeviceClient();
    getWavoipSdkBootstrap.mockResolvedValue({
      data: { device_token: 'token-cached' },
    });
    connectWavoipInbox.mockResolvedValue(client);
    getWavoipClient.mockReturnValue(null);
    getWavoipClientEntry.mockReturnValue({
      client,
      token: 'token-cached',
    });

    const { connectForInbox, syncConnections } = useWavoipConnection();
    await connectForInbox(21);

    getWavoipSdkBootstrap.mockClear();
    connectWavoipInbox.mockClear();
    disconnectWavoipInbox.mockClear();

    await syncConnections('online');

    expect(getWavoipSdkBootstrap).not.toHaveBeenCalled();
    expect(connectWavoipInbox).not.toHaveBeenCalled();
    expect(disconnectWavoipInbox).not.toHaveBeenCalled();
  });

  it('force-reconnects when WebSocket is disconnected for a cached client', async () => {
    const client = createOpenDeviceClient();
    getWavoipSdkBootstrap.mockResolvedValue({
      data: { device_token: 'token-ws' },
    });
    connectWavoipInbox.mockResolvedValue(client);
    getWavoipClient.mockReturnValue(null);
    getWavoipClientEntry.mockReturnValue({
      client,
      token: 'token-ws',
    });

    const { connectForInbox } = useWavoipConnection();
    await connectForInbox(51);

    expect(connectWavoipInbox).toHaveBeenCalledTimes(1);

    connectionStatusHandler?.('disconnected');
    connectWavoipInbox.mockClear();
    disconnectWavoipInbox.mockClear();

    await connectForInbox(51);

    expect(disconnectWavoipInbox).toHaveBeenCalledWith(51);
    expect(connectWavoipInbox).toHaveBeenCalledWith(51, 'token-ws');
  });

  it('reuses a live client on connectForInbox without a second bootstrap fetch', async () => {
    const client = createOpenDeviceClient();
    getWavoipSdkBootstrap.mockResolvedValue({
      data: { device_token: 'token-hot' },
    });
    connectWavoipInbox.mockResolvedValue(client);
    getWavoipClient.mockReturnValue(null);
    getWavoipClientEntry.mockReturnValue({
      client,
      token: 'token-hot',
    });

    const { connectForInbox } = useWavoipConnection();
    await connectForInbox(61);

    getWavoipSdkBootstrap.mockClear();
    connectWavoipInbox.mockClear();

    const reused = await connectForInbox(61);

    expect(reused).toBe(client);
    expect(getWavoipSdkBootstrap).not.toHaveBeenCalled();
    expect(connectWavoipInbox).not.toHaveBeenCalled();
  });

  it('resolves a reconnecting WebSocket wait when connectionStatus becomes connected', async () => {
    const client = createOpenDeviceClient();
    getWavoipSdkBootstrap.mockResolvedValue({
      data: { device_token: 'token-wait' },
    });
    connectWavoipInbox.mockResolvedValue(client);
    getWavoipClient.mockReturnValue(null);
    getWavoipClientEntry.mockReturnValue({
      client,
      token: 'token-wait',
    });

    const { connectForInbox } = useWavoipConnection();
    await connectForInbox(71);

    connectionStatusHandler?.('reconnecting');
    getWavoipSdkBootstrap.mockClear();
    connectWavoipInbox.mockClear();

    const pending = connectForInbox(71);
    connectionStatusHandler?.('connected');
    const reused = await pending;

    expect(reused).toBe(client);
    expect(getWavoipSdkBootstrap).not.toHaveBeenCalled();
    expect(connectWavoipInbox).not.toHaveBeenCalled();
  });

  it('includes bootstrap tokens in the SDK sync key', async () => {
    const client = createOpenDeviceClient();
    getWavoipSdkBootstrap.mockResolvedValue({
      data: { device_token: 'token-sync-key' },
    });
    connectWavoipInbox.mockResolvedValue(client);
    getWavoipClient.mockReturnValue(null);
    getWavoipClientEntry.mockReturnValue({
      client,
      token: 'token-sync-key',
    });

    const { connectForInbox } = useWavoipConnection();
    await connectForInbox(21);

    const store = {
      getters: {
        'inboxes/getInboxes': [
          {
            id: 21,
            channel_type: INBOX_TYPES.WAVOIP,
            current_user_inbox_member: true,
            provider_config: { device_status: 'open' },
          },
        ],
        getCurrentRole: 'agent',
      },
    };

    expect(getWavoipSdkSyncKey(store)).toBe('21:token-sync-key');
  });

  it('keeps isConnecting true until all concurrent connections finish', async () => {
    const client = createOpenDeviceClient();
    let resolveFirst;
    let resolveSecond;

    getWavoipSdkBootstrap.mockResolvedValue({
      data: { device_token: 'token-concurrent' },
    });
    connectWavoipInbox
      .mockImplementationOnce(
        () =>
          new Promise(resolve => {
            resolveFirst = () => resolve(client);
          })
      )
      .mockImplementationOnce(
        () =>
          new Promise(resolve => {
            resolveSecond = () => resolve(client);
          })
      );
    getWavoipClient.mockReturnValue(null);

    const { connectInbox, isConnecting } = useWavoipConnection();
    const first = connectInbox(41);
    const second = connectInbox(42);

    await vi.waitFor(() => {
      expect(isConnecting.value).toBe(true);
    });

    resolveFirst();
    await first;
    expect(isConnecting.value).toBe(true);

    resolveSecond();
    await second;
    expect(isConnecting.value).toBe(false);
  });

  it('removes statusChanged listener via device.off when on returns no unsubscribe', async () => {
    const listeners = new Map();
    const device = {
      status: 'connecting',
      on: (event, handler) => {
        listeners.set(event, handler);
      },
      off: (event, handler) => {
        if (listeners.get(event) === handler) listeners.delete(event);
      },
    };
    const client = {
      getDevices: () => [device],
    };

    const readiness = ensureDeviceReadiness(client);
    listeners.get('statusChanged')?.('open');
    device.status = 'open';
    const result = await readiness;

    expect(result).toEqual({ ready: true, status: 'open' });
    expect(listeners.has('statusChanged')).toBe(false);
  });
});
