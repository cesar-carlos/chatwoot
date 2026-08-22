import { computed, readonly, ref } from 'vue';
import { useStore } from 'vuex';
import InboxesAPI from 'dashboard/api/inboxes';
import { INBOX_TYPES } from 'dashboard/helper/inbox';
import {
  connectWavoipInbox,
  disconnectWavoipInbox,
  getWavoipClient,
  getWavoipClientEntry,
  teardownAllWavoipClients,
  registerDeviceUnsubscriber,
} from 'customDashboard/lib/wavoip/wavoipClientRegistry';
import {
  getPrimaryDevice,
  getDeviceStatus,
  syncDeviceChannelStats,
  wakeDeviceIfNeeded,
} from 'customDashboard/lib/wavoip/wavoipDeviceReadiness';
import {
  setWavoipConnectionStatus,
  setWavoipRestricted,
  setWavoipWhatsAppStatus,
  setWavoipActiveCalls,
  clearWavoipDeviceStatus,
  isWavoipWebSocketDisconnected,
  isWavoipWebSocketReady,
} from 'customDashboard/lib/wavoip/wavoipDeviceStatus';
import { normalizeWavoipDeviceStatus } from 'customDashboard/lib/wavoip/wavoipDeviceStatusNormalize';
import { shouldAgentReceiveWavoipCalls } from 'customDashboard/lib/wavoip/wavoipInboxCallRouting';
import { recordConnectivityIssue } from 'customDashboard/lib/wavoip/wavoipDiagnosticsCollector';
import { getActiveProviderCallId } from 'customDashboard/composables/wavoip/useWavoipActiveCall';
import {
  iceConfigFromBootstrap,
  wavoipIceConfigKey,
} from 'customDashboard/lib/wavoip/wavoipIceConfig';

const BOOTSTRAP_CACHE_TTL_MS = 15_000;
const WS_READY_TIMEOUT_MS = 15_000;
const WS_POLL_INTERVAL_MS = 100;

const connectedInboxIds = new Set();
const connectInboxPromises = new Map();
const sdkBootstrapTokens = new Map();
const bootstrapCache = new Map();
const connectingCount = ref(0);
const isConnecting = computed(() => connectingCount.value > 0);

const isWavoipInbox = inbox => inbox?.channel_type === INBOX_TYPES.WAVOIP;

const isWavoipDeviceOpen = inbox =>
  normalizeWavoipDeviceStatus(inbox?.provider_config?.device_status) === 'open';

const clearBootstrapCache = inboxId => {
  if (inboxId) {
    bootstrapCache.delete(inboxId);
    return;
  }
  bootstrapCache.clear();
};

const fetchBootstrap = async (inboxId, { bypassCache = false } = {}) => {
  if (!bypassCache) {
    const cached = bootstrapCache.get(inboxId);
    if (cached && Date.now() - cached.fetchedAt < BOOTSTRAP_CACHE_TTL_MS) {
      return cached;
    }
  }

  const { data } = await InboxesAPI.getWavoipSdkBootstrap(inboxId);
  const token = data?.device_token;
  const iceConfig = iceConfigFromBootstrap(data);
  if (token) {
    bootstrapCache.set(inboxId, { token, iceConfig, fetchedAt: Date.now() });
  }
  return { token, iceConfig };
};

const getAssignedWavoipInboxes = store => {
  const inboxes = store.getters['inboxes/getInboxes'] || [];
  const isAdministrator = store.getters.getCurrentRole === 'administrator';
  return inboxes.filter(
    inbox =>
      isWavoipInbox(inbox) &&
      shouldAgentReceiveWavoipCalls(inbox, { isAdministrator })
  );
};

const getSdkConnectableWavoipInboxes = store =>
  getAssignedWavoipInboxes(store).filter(isWavoipDeviceOpen);

const wireDeviceListeners = (inboxId, client) => {
  const device = getPrimaryDevice(client);
  if (!device?.on) return;

  setWavoipWhatsAppStatus(inboxId, normalizeWavoipDeviceStatus(device.status));
  setWavoipConnectionStatus(inboxId, device.connectionStatus || 'connected');
  setWavoipRestricted(inboxId, !!device.restricted, device.restrictedUntil);
  syncDeviceChannelStats(inboxId, device);

  const unsubscribers = [];

  unsubscribers.push(
    device.on('statusChanged', status => {
      setWavoipWhatsAppStatus(inboxId, normalizeWavoipDeviceStatus(status));
    })
  );
  unsubscribers.push(
    device.on('connectionStatusChanged', status => {
      setWavoipConnectionStatus(inboxId, status);
    })
  );
  unsubscribers.push(
    device.on('restrictedChanged', (restricted, restrictedUntil) => {
      setWavoipRestricted(inboxId, restricted, restrictedUntil);
    })
  );
  unsubscribers.push(
    device.on('activeCallsChanged', count => {
      setWavoipActiveCalls(inboxId, count);
    })
  );

  registerDeviceUnsubscriber(inboxId, () => {
    unsubscribers.forEach(unsub => {
      try {
        unsub();
      } catch (_) {
        /* noop */
      }
    });
    clearWavoipDeviceStatus(inboxId);
  });
};

async function waitForDeviceOpen(device, timeoutMs = 30_000) {
  if (!device) return false;
  if (normalizeWavoipDeviceStatus(device.status) === 'open') return true;

  return new Promise(resolve => {
    let settled = false;
    let timer;
    let unsubscribeFn;

    let handler;

    function finish(result) {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      if (typeof unsubscribeFn === 'function') {
        unsubscribeFn();
      } else {
        device.off?.('statusChanged', handler);
      }
      resolve(result);
    }

    handler = status => {
      if (normalizeWavoipDeviceStatus(status) === 'open') finish(true);
    };

    unsubscribeFn = device.on?.('statusChanged', handler);
    timer = setTimeout(
      () => finish(normalizeWavoipDeviceStatus(device.status) === 'open'),
      timeoutMs
    );
  });
}

async function ensureDeviceReadiness(client, inboxId) {
  const device = getPrimaryDevice(client);
  if (!device) return { ready: false, status: null };

  if (inboxId) syncDeviceChannelStats(inboxId, device);

  if (await waitForDeviceOpen(device)) {
    return { ready: true, status: device.status };
  }

  const wakeResult = await wakeDeviceIfNeeded(device, { inboxId });
  if (!wakeResult.woke && !wakeResult.ready) {
    return { ready: false, status: device.status };
  }

  const ready = await waitForDeviceOpen(device);
  return { ready, status: device.status };
}

async function ensureDeviceReady(client, inboxId) {
  const { ready } = await ensureDeviceReadiness(client, inboxId);
  return ready;
}

/**
 * Wait until Device.connectionStatus is connected (or still unknown).
 * `disconnected` is transient — the SDK retries a few times — so we wait the
 * full timeout instead of failing on the first drop.
 */
async function waitForWebSocketConnected(
  inboxId,
  timeoutMs = WS_READY_TIMEOUT_MS
) {
  if (isWavoipWebSocketReady(inboxId)) return true;

  return new Promise(resolve => {
    const startedAt = Date.now();
    const timer = setInterval(() => {
      if (isWavoipWebSocketReady(inboxId)) {
        clearInterval(timer);
        resolve(true);
        return;
      }
      if (Date.now() - startedAt >= timeoutMs) {
        clearInterval(timer);
        resolve(isWavoipWebSocketReady(inboxId));
      }
    }, WS_POLL_INTERVAL_MS);
  });
}

export function useWavoipConnection() {
  const store = useStore();

  const establishInboxConnection = async (inboxId, token, iceConfig) => {
    if (!token) return null;

    const inFlight = connectInboxPromises.get(inboxId);
    if (inFlight) return inFlight;

    const promise = (async () => {
      connectingCount.value += 1;
      try {
        sdkBootstrapTokens.set(inboxId, token);
        const client = iceConfig
          ? await connectWavoipInbox(inboxId, token, { iceConfig })
          : await connectWavoipInbox(inboxId, token);
        wireDeviceListeners(inboxId, client);
        connectedInboxIds.add(inboxId);
        return client;
      } catch (error) {
        connectedInboxIds.delete(inboxId);
        sdkBootstrapTokens.delete(inboxId);
        await disconnectWavoipInbox(inboxId);
        recordConnectivityIssue(
          inboxId,
          null,
          error?.message || 'SDK connect failed'
        );
        throw error;
      } finally {
        connectingCount.value = Math.max(0, connectingCount.value - 1);
        connectInboxPromises.delete(inboxId);
      }
    })();

    connectInboxPromises.set(inboxId, promise);
    return promise;
  };

  const dropInboxConnection = async inboxId => {
    const existingEntry = getWavoipClientEntry(inboxId);
    connectedInboxIds.delete(inboxId);
    connectInboxPromises.delete(inboxId);
    if (existingEntry) await disconnectWavoipInbox(inboxId);
  };

  const connectInbox = async (inboxId, { forceReconnect = false } = {}) => {
    if (!inboxId) return null;

    if (connectedInboxIds.has(inboxId)) {
      const existingEntry = getWavoipClientEntry(inboxId);
      // Bypass cache so rotated tokens / ICE config are detected promptly.
      const bootstrap = await fetchBootstrap(inboxId, {
        bypassCache: true,
      });
      const freshToken = bootstrap.token;
      const iceConfig = bootstrap.iceConfig;
      if (freshToken) sdkBootstrapTokens.set(inboxId, freshToken);

      const tokenChanged =
        Boolean(freshToken) && existingEntry?.token !== freshToken;
      const iceChanged =
        wavoipIceConfigKey(iceConfig) !== (existingEntry?.iceConfigKey || '');
      // Dead WebSocket: cached client is unusable for offer/accept — rebuild.
      const mustReconnect =
        forceReconnect ||
        tokenChanged ||
        iceChanged ||
        isWavoipWebSocketDisconnected(inboxId);

      if (!mustReconnect && freshToken && existingEntry?.token === freshToken) {
        return existingEntry.client;
      }

      await dropInboxConnection(inboxId);
      return establishInboxConnection(
        inboxId,
        freshToken || existingEntry?.token,
        iceConfig
      );
    }

    const { token, iceConfig } = await fetchBootstrap(inboxId);
    return establishInboxConnection(inboxId, token, iceConfig);
  };

  const connectForInbox = async (inboxId, options = {}) => {
    let client = await connectInbox(inboxId, options);
    if (!client) return null;
    await ensureDeviceReady(client, inboxId);

    if (await waitForWebSocketConnected(inboxId)) return client;

    // First attempt settled on disconnected (or timed out while reconnecting).
    // Force one full SDK rebuild before giving up.
    recordConnectivityIssue(
      inboxId,
      null,
      'WebSocket not ready after connect — forcing reconnect'
    );
    client = await connectInbox(inboxId, { forceReconnect: true });
    if (!client) return null;
    await ensureDeviceReady(client, inboxId);
    if (!(await waitForWebSocketConnected(inboxId))) return null;
    return client;
  };

  const disconnectInbox = async inboxId => {
    connectedInboxIds.delete(inboxId);
    connectInboxPromises.delete(inboxId);
    sdkBootstrapTokens.delete(inboxId);
    clearBootstrapCache(inboxId);
    await disconnectWavoipInbox(inboxId);
    clearWavoipDeviceStatus(inboxId);
  };

  const syncConnections = async availability => {
    if (availability !== 'online') {
      if (getActiveProviderCallId()) return;

      connectedInboxIds.clear();
      connectInboxPromises.clear();
      sdkBootstrapTokens.clear();
      clearBootstrapCache();
      await teardownAllWavoipClients();
      return;
    }

    const wavoipInboxes = getSdkConnectableWavoipInboxes(store);
    const targetIds = new Set(wavoipInboxes.map(inbox => inbox.id));

    await Promise.all(
      [...connectedInboxIds]
        .filter(id => !targetIds.has(id))
        .map(id => disconnectInbox(id))
    );

    await Promise.all(
      [...targetIds].map(async id => {
        try {
          await connectInbox(id);
        } catch (_) {
          /* recorded in connectInbox */
        }
      })
    );
  };

  const wakeUpInboxDevice = async inboxId => {
    const client = await connectInbox(inboxId);
    const device = getPrimaryDevice(client);
    syncDeviceChannelStats(inboxId, device);
    const result = await wakeDeviceIfNeeded(device, { inboxId });
    if (result.error) throw result.error;
    return result.ready || result.woke;
  };

  return {
    isConnecting: readonly(isConnecting),
    connectInbox,
    connectForInbox,
    disconnectInbox,
    syncConnections,
    ensureDeviceReady,
    ensureDeviceReadiness,
    getDeviceStatus,
    getWavoipClient,
    wakeUpInboxDevice,
  };
}

export {
  teardownAllWavoipClients,
  ensureDeviceReadiness,
  getDeviceStatus,
  wakeDeviceIfNeeded,
  syncDeviceChannelStats,
};

export function getWavoipSdkSyncKey(store) {
  return getSdkConnectableWavoipInboxes(store)
    .map(inbox => {
      const token =
        sdkBootstrapTokens.get(inbox.id) ??
        getWavoipClientEntry(inbox.id)?.token ??
        '';
      return `${inbox.id}:${token}`;
    })
    .sort((a, b) => a.localeCompare(b))
    .join(',');
}
