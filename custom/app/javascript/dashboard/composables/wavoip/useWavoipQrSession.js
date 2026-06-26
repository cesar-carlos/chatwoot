import { ref, unref } from 'vue';
import InboxesAPI from 'dashboard/api/inboxes';
import { useWavoipConnection } from 'customDashboard/composables/wavoip/useWavoipConnection';
import { getWavoipClient } from 'customDashboard/lib/wavoip/wavoipClientRegistry';
import { getPrimaryDevice } from 'customDashboard/lib/wavoip/wavoipDeviceReadiness';
import { unwrapWavoipSdkResult } from 'customDashboard/lib/wavoip/wavoipSdkResult';
import { buildQrDataUrl } from 'customDashboard/lib/wavoip/wavoipQrImage';

/* eslint-disable no-use-before-define -- QR expiry timer and session share refreshQr */

const QR_EXPIRY_MS = 45_000;
const STATUS_POLL_MS = 4_000;

export function useWavoipQrSession({
  inboxId,
  phoneNumber,
  onConnected,
  onPhoneMismatch,
}) {
  const { connectInbox } = useWavoipConnection();

  const whatsAppStatus = ref('');
  const qrDataUrl = ref('');
  const pairingCode = ref('');
  const linkedPhone = ref('');
  const isLoading = ref(false);
  const isRefreshing = ref(false);
  const qrRefreshError = ref(false);

  let deviceUnsubscribers = [];
  let expiryTimer = null;
  let statusPollTimer = null;
  let sdkConnected = false;
  let sessionStartedConnected = false;
  let hasEmittedConnected = false;

  function isConnected() {
    return whatsAppStatus.value === 'open';
  }

  function needsQr() {
    return (
      ['close', 'connecting'].includes(whatsAppStatus.value) ||
      Boolean(qrDataUrl.value)
    );
  }

  function clearDeviceListeners() {
    deviceUnsubscribers.forEach(unsub => {
      try {
        unsub();
      } catch (_) {
        /* noop */
      }
    });
    deviceUnsubscribers = [];
  }

  function clearExpiryTimer() {
    if (expiryTimer) {
      clearTimeout(expiryTimer);
      expiryTimer = null;
    }
  }

  function clearStatusPoll() {
    if (statusPollTimer) {
      clearInterval(statusPollTimer);
      statusPollTimer = null;
    }
  }

  function stopSession() {
    clearDeviceListeners();
    clearExpiryTimer();
    clearStatusPoll();
  }

  async function pollInboxStatus() {
    const id = unref(inboxId);
    if (!id || isConnected()) return;

    try {
      // force: false — uses 15-second server cache; DB status updated by webhook is still read
      const { data } = await InboxesAPI.getWavoipDeviceStatus(id, {
        force: false,
      });
      applyStatus(data?.device_status);
    } catch (_) {
      /* keep last known state */
    }
  }

  function startStatusPolling() {
    clearStatusPoll();
    pollInboxStatus();
    statusPollTimer = setInterval(pollInboxStatus, STATUS_POLL_MS);
  }

  async function ensureSdkConnected() {
    const id = unref(inboxId);
    if (!id) return null;

    if (sdkConnected) {
      return getPrimaryDevice(getWavoipClient(id));
    }

    await connectInbox(id);
    const device = getPrimaryDevice(getWavoipClient(id));
    wireDeviceListeners(device);
    syncFromDevice(device);
    sdkConnected = true;
    return device;
  }

  async function applyQrString(qrString) {
    if (!qrString?.trim()) {
      qrDataUrl.value = '';
      return;
    }

    try {
      qrDataUrl.value = await buildQrDataUrl(qrString);
      qrRefreshError.value = false;
    } catch (_) {
      qrRefreshError.value = true;
    }
  }

  function applyStatus(status) {
    if (!status) return;

    whatsAppStatus.value = status;

    if (status === 'open') {
      qrDataUrl.value = '';
      pairingCode.value = '';
      clearExpiryTimer();
      clearStatusPoll();
      if (!sessionStartedConnected && !hasEmittedConnected) {
        hasEmittedConnected = true;
        onConnected?.();
      }
      return;
    }

    if (status !== 'connecting' && status !== 'close') {
      qrDataUrl.value = '';
    }
  }

  async function applyQrPayload(data) {
    if (data?.device_status) {
      applyStatus(data.device_status);
    }

    if (isConnected()) return true;

    if (data?.qr_code) {
      await applyQrString(data.qr_code);
      return Boolean(qrDataUrl.value);
    }

    if (data?.qrcode_base64) {
      qrDataUrl.value = data.qrcode_base64;
      qrRefreshError.value = false;
      return true;
    }

    return false;
  }

  async function fetchQrFromBackend({ refresh = false } = {}) {
    const id = unref(inboxId);
    if (!id) return false;

    const { data } = await InboxesAPI.getWavoipQr(id, { refresh });
    return applyQrPayload(data);
  }

  function armQrExpiryTimer() {
    clearExpiryTimer();
    expiryTimer = setTimeout(() => {
      if (!isConnected()) {
        refreshQr({ restart: false }).catch(() => {});
      }
    }, QR_EXPIRY_MS);
  }

  function wireDeviceListeners(device) {
    clearDeviceListeners();
    if (!device?.on) return;

    deviceUnsubscribers.push(
      device.on('qrCodeChanged', code => {
        if (code) {
          applyQrString(code);
        } else {
          qrDataUrl.value = '';
        }
      })
    );
    deviceUnsubscribers.push(
      device.on('statusChanged', status => {
        applyStatus(status);
      })
    );
    deviceUnsubscribers.push(
      device.on('contactChanged', contact => {
        linkedPhone.value = contact?.phone || '';
        const expectedPhone = unref(phoneNumber);
        if (
          contact?.phone &&
          expectedPhone &&
          contact.phone !== expectedPhone &&
          onPhoneMismatch
        ) {
          onPhoneMismatch(contact.phone);
        }
      })
    );
  }

  function syncFromDevice(device) {
    if (!device) return;

    applyStatus(device.status);
    if (device.qrCode) {
      applyQrString(device.qrCode);
    }
    if (device.contact?.phone) {
      linkedPhone.value = device.contact.phone;
    }
  }

  async function refreshQr({ restart = false } = {}) {
    const id = unref(inboxId);
    if (!id || isRefreshing.value) return;

    isRefreshing.value = true;
    qrRefreshError.value = false;
    pairingCode.value = '';

    try {
      const loaded = await fetchQrFromBackend({ refresh: restart });
      if (!loaded && !isConnected()) {
        qrRefreshError.value = true;
      } else if (!isConnected()) {
        armQrExpiryTimer();
      }
    } catch (_) {
      if (!isConnected()) {
        qrRefreshError.value = true;
      }
      throw _;
    } finally {
      isRefreshing.value = false;
    }
  }

  async function startSession({ fetchFreshQr = false } = {}) {
    const id = unref(inboxId);
    if (!id) return;

    hasEmittedConnected = false;
    sdkConnected = false;
    isLoading.value = true;
    qrRefreshError.value = false;

    try {
      // Single request: returns device_status + QR image together
      await fetchQrFromBackend({ refresh: fetchFreshQr });
      sessionStartedConnected = isConnected();
      hasEmittedConnected = sessionStartedConnected;

      if (!isConnected()) {
        // Only flag an error when the device is closed (disconnected) and we
        // have no QR to show. A 'connecting' status without QR is a normal
        // transitional state — the QR will arrive via polling or the expiry
        // refresh, so show a waiting spinner instead of an error.
        if (!qrDataUrl.value && whatsAppStatus.value !== 'connecting') {
          qrRefreshError.value = true;
        }
        startStatusPolling();
        armQrExpiryTimer();
      }
    } catch (error) {
      if (!qrDataUrl.value && !isConnected()) {
        qrRefreshError.value = true;
      }
      throw error;
    } finally {
      isLoading.value = false;
    }
  }

  function handleQrImageError() {
    qrDataUrl.value = '';
    qrRefreshError.value = true;
  }

  async function requestPairingCode() {
    const id = unref(inboxId);
    const phone = unref(phoneNumber);
    if (!id || !phone) return;

    const device = await ensureSdkConnected();
    if (!device?.pairingCode) {
      throw new Error('Wavoip device unavailable');
    }

    const raw = await device.pairingCode(phone);
    const { pairingCode: code, err } = unwrapWavoipSdkResult(
      raw,
      'pairingCode'
    );
    if (err) {
      throw new Error(
        typeof err === 'string' ? err : err?.message || 'Pairing failed'
      );
    }
    pairingCode.value = code || '';
  }

  function clearQrState() {
    qrDataUrl.value = '';
    pairingCode.value = '';
    linkedPhone.value = '';
    hasEmittedConnected = false;
    sessionStartedConnected = false;
    sdkConnected = false;
  }

  function hasSdkConnection() {
    return sdkConnected;
  }

  return {
    whatsAppStatus,
    qrDataUrl,
    pairingCode,
    linkedPhone,
    isLoading,
    isRefreshing,
    qrRefreshError,
    isConnected,
    needsQr,
    hasSdkConnection,
    startSession,
    stopSession,
    requestPairingCode,
    refreshQr,
    handleQrImageError,
    clearQrState,
  };
}
