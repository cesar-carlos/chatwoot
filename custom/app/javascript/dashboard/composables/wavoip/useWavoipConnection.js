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
} from 'customDashboard/lib/wavoip/wavoipDeviceStatus';
import { shouldAgentReceiveWavoipCalls } from 'customDashboard/lib/wavoip/wavoipInboxCallRouting';
import { recordConnectivityIssue } from 'customDashboard/lib/wavoip/wavoipDiagnosticsCollector';
import { getActiveProviderCallId } from 'customDashboard/composables/wavoip/useWavoipActiveCall';

const BOOTSTRAP_CACHE_TTL_MS = 15_000;

const connectedInboxIds = new Set();
const connectInboxPromises = new Map();
const sdkBootstrapTokens = new Map();
const bootstrapCache = new Map();
const connectingCount = ref(0);
const isConnecting = computed(() => connectingCount.value > 0);

const isWavoipInbox = inbox => inbox?.channel_type === INBOX_TYPES.WAVOIP;

const isWavoipDeviceOpen = inbox =>
  inbox?.provider_config?.device_status === 'open';

const clearBootstrapCache = inboxId => {
  if (inboxId) {
    bootstrapCache.delete(inboxId);
    return;
  }
  bootstrapCache.clear();
};

const fetchBootstrapToken = async inboxId => {
  const cached = bootstrapCache.get(inboxId);
  if (cached && Date.now() - cached.fetchedAt < BOOTSTRAP_CACHE_TTL_MS) {
    return cached.token;
  }

  const { data } = await InboxesAPI.getWavoipSdkBootstrap(inboxId);
  const token = data?.device_token;
  if (token) {
    bootstrapCache.set(inboxId, { token, fetchedAt: Date.now() });
  }
  return token;
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

  setWavoipWhatsAppStatus(inboxId, device.status);
  setWavoipConnectionStatus(inboxId, device.connectionStatus || 'connected');
  setWavoipRestricted(inboxId, !!device.restricted, device.restrictedUntil);
  syncDeviceChannelStats(inboxId, device);

  const unsubscribers = [];

  unsubscribers.push(
    device.on('statusChanged', status => {
      setWavoipWhatsAppStatus(inboxId, status);
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
  if (device.status === 'open') return true;

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
      if (status === 'open') finish(true);
    };

    unsubscribeFn = device.on?.('statusChanged', handler);
    timer = setTimeout(() => finish(device.status === 'open'), timeoutMs);
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

export function useWavoipConnection() {
  const store = useStore();

  const establishInboxConnection = async (inboxId, token) => {
    if (!token) return null;

    const inFlight = connectInboxPromises.get(inboxId);
    if (inFlight) return inFlight;

    const promise = (async () => {
      connectingCount.value += 1;
      try {
        sdkBootstrapTokens.set(inboxId, token);
        const client = await connectWavoipInbox(inboxId, token);
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

  const connectInbox = async inboxId => {
    if (!inboxId) return null;

    if (connectedInboxIds.has(inboxId)) {
      const existingEntry = getWavoipClientEntry(inboxId);
      const freshToken = await fetchBootstrapToken(inboxId);
      if (freshToken) sdkBootstrapTokens.set(inboxId, freshToken);
      if (freshToken && existingEntry?.token === freshToken) {
        return existingEntry.client;
      }
      connectedInboxIds.delete(inboxId);
      connectInboxPromises.delete(inboxId);
      if (existingEntry) await disconnectWavoipInbox(inboxId);
      return establishInboxConnection(inboxId, freshToken);
    }

    const token = await fetchBootstrapToken(inboxId);
    return establishInboxConnection(inboxId, token);
  };

  const connectForInbox = async inboxId => {
    const client = await connectInbox(inboxId);
    if (!client) return null;
    await ensureDeviceReady(client, inboxId);
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
