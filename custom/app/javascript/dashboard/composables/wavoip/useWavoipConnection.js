import { readonly, ref } from 'vue';
import { useStore } from 'vuex';
import InboxesAPI from 'dashboard/api/inboxes';
import { INBOX_TYPES } from 'dashboard/helper/inbox';
import {
  connectWavoipInbox,
  disconnectWavoipInbox,
  getWavoipClient,
  teardownAllWavoipClients,
  registerDeviceUnsubscriber,
} from 'customDashboard/lib/wavoip/wavoipClientRegistry';
import {
  getPrimaryDevice,
  getDeviceStatus,
} from 'customDashboard/lib/wavoip/wavoipDeviceReadiness';
import {
  setWavoipConnectionStatus,
  setWavoipRestricted,
  setWavoipWhatsAppStatus,
  clearWavoipDeviceStatus,
} from 'customDashboard/lib/wavoip/wavoipDeviceStatus';
import { shouldAgentReceiveWavoipCalls } from 'customDashboard/lib/wavoip/wavoipInboxCallRouting';
import { recordConnectivityIssue } from 'customDashboard/lib/wavoip/wavoipDiagnosticsCollector';

const connectedInboxIds = new Set();
const connectInboxPromises = new Map();
const isConnecting = ref(false);

const isWavoipInbox = inbox => inbox?.channel_type === INBOX_TYPES.WAVOIP;

const isWavoipDeviceOpen = inbox =>
  inbox?.provider_config?.device_status === 'open';

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
    let unsubscribe;

    const finish = result => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      unsubscribe?.();
      resolve(result);
    };

    unsubscribe = device.on?.('statusChanged', status => {
      if (status === 'open') finish(true);
    });

    timer = setTimeout(() => finish(device.status === 'open'), timeoutMs);
  });
}

async function ensureDeviceReadiness(client) {
  const device = getPrimaryDevice(client);
  if (!device) return { ready: false, status: null };

  if (await waitForDeviceOpen(device)) {
    return { ready: true, status: device.status };
  }

  if (device.status === 'hibernating') {
    try {
      await device.wakeUp?.();
    } catch (error) {
      // eslint-disable-next-line no-console
      console.debug('[Wavoip] device wakeUp failed', error);
      return { ready: false, status: device.status };
    }
  }

  const ready = await waitForDeviceOpen(device);
  return { ready, status: device.status };
}

async function ensureDeviceReady(client) {
  const { ready } = await ensureDeviceReadiness(client);
  return ready;
}

export function useWavoipConnection() {
  const store = useStore();

  const connectInbox = async inboxId => {
    if (!inboxId) return null;

    if (connectedInboxIds.has(inboxId)) {
      return getWavoipClient(inboxId);
    }

    const inFlight = connectInboxPromises.get(inboxId);
    if (inFlight) return inFlight;

    const promise = (async () => {
      isConnecting.value = true;
      try {
        const { data } = await InboxesAPI.getWavoipSdkBootstrap(inboxId);
        const token = data?.device_token;
        if (!token) return null;

        const client = await connectWavoipInbox(inboxId, token);
        wireDeviceListeners(inboxId, client);
        connectedInboxIds.add(inboxId);
        return client;
      } catch (error) {
        connectedInboxIds.delete(inboxId);
        await disconnectWavoipInbox(inboxId);
        recordConnectivityIssue(
          inboxId,
          null,
          error?.message || 'SDK connect failed'
        );
        throw error;
      } finally {
        isConnecting.value = false;
        connectInboxPromises.delete(inboxId);
      }
    })();

    connectInboxPromises.set(inboxId, promise);
    return promise;
  };

  const connectForInbox = async inboxId => {
    const client = await connectInbox(inboxId);
    if (!client) return null;
    await ensureDeviceReady(client);
    return client;
  };

  const disconnectInbox = async inboxId => {
    connectedInboxIds.delete(inboxId);
    connectInboxPromises.delete(inboxId);
    await disconnectWavoipInbox(inboxId);
    clearWavoipDeviceStatus(inboxId);
  };

  const syncConnections = async availability => {
    if (availability !== 'online') {
      connectedInboxIds.clear();
      connectInboxPromises.clear();
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
    if (!device?.wakeUp) return false;
    return device.wakeUp();
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

export { teardownAllWavoipClients, ensureDeviceReadiness, getDeviceStatus };

export function getWavoipSdkSyncKey(store) {
  return getSdkConnectableWavoipInboxes(store)
    .map(inbox => inbox.id)
    .sort((a, b) => a - b)
    .join(',');
}
