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

const QR_FALLBACK_MS = 10_000;

export function useWavoipQrSession({
  inboxId,
  phoneNumber,
  onConnected,
  onPhoneMismatch,
}) {
  const { connectForInbox, wakeUpInboxDevice } = useWavoipConnection();

  const whatsAppStatus = ref('');
  const qrDataUrl = ref('');
  const pairingCode = ref('');
  const linkedPhone = ref('');
  const isLoading = ref(false);
  const isRefreshing = ref(false);
  const qrRefreshError = ref(false);

  let deviceUnsubscribers = [];
  let fallbackTimer = null;
  let hasEmittedConnected = false;
  let cachedDeviceToken = null;

  function isConnected() {
    return whatsAppStatus.value === 'open';
  }

  function needsQr() {
    return ['close', 'connecting'].includes(whatsAppStatus.value) || Boolean(qrDataUrl.value);
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

  function stopSession() {
    clearDeviceListeners();
    clearFallbackTimer();
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
      if (!hasEmittedConnected) {
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
        if (
          contact?.phone &&
          phoneNumber &&
          contact.phone !== phoneNumber &&
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

  async function startSession() {
    const id = unref(inboxId);
    if (!id) return;

    hasEmittedConnected = false;
    isLoading.value = true;
    qrRefreshError.value = false;

    try {
      const { data } = await InboxesAPI.getWavoipSdkBootstrap(id);
      cachedDeviceToken = data?.device_token || null;

      await connectForInbox(id);
      const device = getPrimaryDevice(getWavoipClient(id));
      const wasConnected = device?.status === 'open';
      wireDeviceListeners(device);
      syncFromDevice(device);
      hasEmittedConnected = wasConnected;

      if (!isConnected() && !qrDataUrl.value) {
        armFallbackTimer();
      }
    } catch (_) {
      qrRefreshError.value = true;
    } finally {
      isLoading.value = false;
    }
  }

  async function requestPairingCode() {
    const id = unref(inboxId);
    const phone = unref(phoneNumber);
    if (!id || !phone) return;

    const device = getPrimaryDevice(getWavoipClient(id));
    if (!device?.pairingCode) return;

    const raw = await device.pairingCode(phone);
    const { pairingCode: code, err } = unwrapWavoipSdkResult(raw, 'pairingCode');
    if (err) {
      throw new Error(typeof err === 'string' ? err : err?.message || 'Pairing failed');
    }
    pairingCode.value = code || '';
  }

  async function refreshQr() {
    const id = unref(inboxId);
    if (!id || isRefreshing.value) return;

    isRefreshing.value = true;
    qrRefreshError.value = false;
    pairingCode.value = '';

    try {
      const device = getPrimaryDevice(getWavoipClient(id));
      if (!device) {
        qrRefreshError.value = true;
        return;
      }

      if (device.status === 'hibernating') {
        await wakeUpInboxDevice(id);
      } else if (device.restart) {
        await device.restart();
      }

      syncFromDevice(getPrimaryDevice(getWavoipClient(id)));

      if (!isConnected() && !qrDataUrl.value && cachedDeviceToken) {
        qrDataUrl.value = withCacheBust(buildWavoipQrImageUrl(cachedDeviceToken));
      }

      if (!isConnected() && !qrDataUrl.value) {
        armFallbackTimer();
      }
    } catch (_) {
      qrRefreshError.value = true;
    } finally {
      isRefreshing.value = false;
    }
  }

  function clearQrState() {
    qrDataUrl.value = '';
    pairingCode.value = '';
    linkedPhone.value = '';
    hasEmittedConnected = false;
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
