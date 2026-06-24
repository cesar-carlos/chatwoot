import { ref, unref } from 'vue';
import InboxesAPI from 'dashboard/api/inboxes';
import { useWavoipConnection } from 'customDashboard/composables/wavoip/useWavoipConnection';
import { getWavoipClient } from 'customDashboard/lib/wavoip/wavoipClientRegistry';
import { getPrimaryDevice } from 'customDashboard/lib/wavoip/wavoipDeviceReadiness';
import { unwrapWavoipSdkResult } from 'customDashboard/lib/wavoip/wavoipSdkResult';
import {
  buildQrDataUrl,
  buildWavoipQrImageUrl,
  withCacheBust,
} from 'customDashboard/lib/wavoip/wavoipQrImage';

/* eslint-disable no-use-before-define -- QR expiry timer and session share refreshQr */

const QR_FALLBACK_MS = 10_000;
const QR_EXPIRY_MS = 45_000;
const STATUS_POLL_MS = 4_000;

export function useWavoipQrSession({
  inboxId,
  phoneNumber,
  onConnected,
  onPhoneMismatch,
}) {
  const { connectInbox, wakeUpInboxDevice } = useWavoipConnection();

  const whatsAppStatus = ref('');
  const qrDataUrl = ref('');
  const pairingCode = ref('');
  const linkedPhone = ref('');
  const isLoading = ref(false);
  const isRefreshing = ref(false);
  const qrRefreshError = ref(false);

  let deviceUnsubscribers = [];
  let fallbackTimer = null;
  let expiryTimer = null;
  let statusPollTimer = null;
  let sdkConnected = false;
  let sessionStartedConnected = false;
  let hasEmittedConnected = false;
  let cachedDeviceToken = null;

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

  function clearFallbackTimer() {
    if (fallbackTimer) {
      clearTimeout(fallbackTimer);
      fallbackTimer = null;
    }
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
    clearFallbackTimer();
    clearExpiryTimer();
    clearStatusPoll();
  }

  async function pollInboxStatus() {
    const id = unref(inboxId);
    if (!id || isConnected()) return;

    try {
      const { data } = await InboxesAPI.show(id);
      applyStatus(data?.provider_config?.device_status);
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
      clearFallbackTimer();
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

  function armFallbackTimer() {
    clearFallbackTimer();
    fallbackTimer = setTimeout(() => {
      if (isConnected() || qrDataUrl.value || !cachedDeviceToken) return;
      qrDataUrl.value = withCacheBust(buildWavoipQrImageUrl(cachedDeviceToken));
      qrRefreshError.value = false;
    }, QR_FALLBACK_MS);
  }

  function applyFallbackQrImage() {
    if (!cachedDeviceToken || isConnected()) return false;

    qrDataUrl.value = withCacheBust(buildWavoipQrImageUrl(cachedDeviceToken));
    qrRefreshError.value = false;
    return true;
  }

  function armQrExpiryTimer() {
    clearExpiryTimer();
    expiryTimer = setTimeout(() => {
      if (!isConnected()) {
        refreshQr({ soft: true }).catch(() => {});
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

  async function refreshQr({ soft = true } = {}) {
    const id = unref(inboxId);
    if (!id || isRefreshing.value) return;

    isRefreshing.value = true;
    qrRefreshError.value = false;
    pairingCode.value = '';

    try {
      if (soft) {
        if (applyFallbackQrImage()) {
          armQrExpiryTimer();
          return;
        }
        throw new Error('Wavoip device token unavailable');
      }

      const device = await ensureSdkConnected();
      if (!device) {
        if (applyFallbackQrImage()) return;
        qrRefreshError.value = true;
        throw new Error('Wavoip device unavailable');
      }

      if (device.status === 'hibernating') {
        await wakeUpInboxDevice(id);
      } else if (device.restart) {
        await device.restart();
      }

      syncFromDevice(getPrimaryDevice(getWavoipClient(id)));

      if (!isConnected() && !qrDataUrl.value) {
        applyFallbackQrImage();
      }

      if (!isConnected() && !qrDataUrl.value) {
        armFallbackTimer();
      }

      if (!isConnected()) {
        armQrExpiryTimer();
      }
    } catch (error) {
      if (!applyFallbackQrImage()) {
        qrRefreshError.value = true;
      }
      throw error;
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
      const { data } = await InboxesAPI.getWavoipSdkBootstrap(id);
      cachedDeviceToken = data?.device_token || null;

      if (!cachedDeviceToken) {
        throw new Error('Wavoip device token unavailable');
      }

      try {
        const { data: inbox } = await InboxesAPI.show(id);
        applyStatus(inbox?.provider_config?.device_status);
        sessionStartedConnected = isConnected();
        hasEmittedConnected = sessionStartedConnected;
      } catch (_) {
        whatsAppStatus.value = whatsAppStatus.value || 'connecting';
      }

      if (!isConnected()) {
        applyFallbackQrImage();
        startStatusPolling();
        armQrExpiryTimer();
      }

      if (fetchFreshQr && !isConnected()) {
        await refreshQr({ soft: true });
      }
    } catch (error) {
      if (!qrDataUrl.value) {
        qrRefreshError.value = true;
      }
      throw error;
    } finally {
      isLoading.value = false;
    }
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
    startSession,
    stopSession,
    requestPairingCode,
    refreshQr,
    clearQrState,
  };
}
