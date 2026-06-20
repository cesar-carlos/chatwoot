import { readonly, ref } from 'vue';
import { useStore } from 'vuex';
import InboxesAPI from 'dashboard/api/inboxes';
import { INBOX_TYPES } from 'dashboard/helper/inbox';
import {
  connectWavoipInbox,
  disconnectWavoipInbox,
  getWavoipClient,
  teardownAllWavoipClients,
} from 'customDashboard/lib/wavoip/wavoipClientRegistry';

const connectedInboxIds = new Set();
const isConnecting = ref(false);

const isWavoipInbox = inbox => inbox?.channel_type === INBOX_TYPES.WAVOIP;

const getAssignedWavoipInboxes = store => {
  const inboxes = store.getters['inboxes/getInboxes'] || [];
  return inboxes.filter(isWavoipInbox);
};

async function waitForDeviceOpen(device, timeoutMs = 30_000) {
  if (!device) return false;
  if (device.status === 'open') return true;

  return new Promise(resolve => {
    let settled = false;
    const finish = result => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      unsubscribe?.();
      resolve(result);
    };

    const unsubscribe = device.on?.('statusChanged', status => {
      if (status === 'open') finish(true);
    });

    const timer = setTimeout(() => finish(device.status === 'open'), timeoutMs);
  });
}

async function ensureDeviceReady(client) {
  const devices = client?.getDevices?.() || [];
  const device = devices[0];
  if (!device) return false;

  if (await waitForDeviceOpen(device)) return true;

  if (device.status === 'hibernating') {
    try {
      await device.wakeUp?.();
    } catch (error) {
      // eslint-disable-next-line no-console
      console.debug('[Wavoip] device wakeUp failed', error);
      return false;
    }
  }

  return waitForDeviceOpen(device);
}

export function useWavoipConnection() {
  const store = useStore();

  const connectInbox = async inboxId => {
    if (!inboxId || connectedInboxIds.has(inboxId)) {
      return getWavoipClient(inboxId);
    }

    isConnecting.value = true;
    try {
      const { data } = await InboxesAPI.getWavoipSdkBootstrap(inboxId);
      const token = data?.device_token;
      if (!token) return null;

      const client = await connectWavoipInbox(inboxId, token);
      connectedInboxIds.add(inboxId);
      return client;
    } finally {
      isConnecting.value = false;
    }
  };

  const connectForInbox = async inboxId => {
    const client = await connectInbox(inboxId);
    if (!client) return null;
    await ensureDeviceReady(client);
    return client;
  };

  const disconnectInbox = async inboxId => {
    connectedInboxIds.delete(inboxId);
    await disconnectWavoipInbox(inboxId);
  };

  const syncConnections = async availability => {
    if (availability !== 'online') {
      connectedInboxIds.clear();
      await teardownAllWavoipClients();
      return;
    }

    const wavoipInboxes = getAssignedWavoipInboxes(store);
    const targetIds = new Set(wavoipInboxes.map(inbox => inbox.id));

    await Promise.all(
      [...connectedInboxIds]
        .filter(id => !targetIds.has(id))
        .map(id => disconnectInbox(id))
    );

    await Promise.all([...targetIds].map(id => connectInbox(id)));
  };

  return {
    isConnecting: readonly(isConnecting),
    connectForInbox,
    disconnectInbox,
    syncConnections,
    ensureDeviceReady,
    getWavoipClient,
  };
}

export { teardownAllWavoipClients };
