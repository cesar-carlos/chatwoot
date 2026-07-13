import { getWavoipClientEntry } from 'customDashboard/lib/wavoip/wavoipClientRegistry';
import { getWavoipDeviceStatus } from 'customDashboard/lib/wavoip/wavoipDeviceStatus';

const MAX_ENTRIES = 50;
const WAVOIP_SDK_VERSION = '2.6.3';

const iceDiagnostics = [];
const connectivityIssues = [];
const callErrors = [];
const callStats = [];

const pushEntry = (buffer, entry) => {
  buffer.push({ ...entry, at: new Date().toISOString() });
  if (buffer.length > MAX_ENTRIES) buffer.shift();
};

export function recordIceDiagnostics(inboxId, callId, payload) {
  pushEntry(iceDiagnostics, { inboxId, callId, payload });
}

export function recordConnectivityIssue(inboxId, callId, issue) {
  pushEntry(connectivityIssues, { inboxId, callId, issue });
}

export function recordCallError(inboxId, callId, error) {
  pushEntry(callErrors, { inboxId, callId, error });
}

export function recordCallStats(inboxId, callId, stats) {
  pushEntry(callStats, { inboxId, callId, stats });
}

function buildDeviceSnapshot(inboxId) {
  if (!inboxId) return null;

  const status = getWavoipDeviceStatus(inboxId);
  const entry = getWavoipClientEntry(inboxId);

  return {
    whatsAppStatus: status.whatsAppStatus.value,
    connectionStatus: status.connectionStatus.value,
    activeCalls: status.activeCalls.value,
    numChannels: status.numChannels.value,
    isRestricted: status.isRestricted.value,
    restrictedUntil: status.restrictedUntil.value,
    sdkConnected: Boolean(entry),
  };
}

export function exportWavoipDiagnostics({ inboxId, callId } = {}) {
  return JSON.stringify(
    {
      generatedAt: new Date().toISOString(),
      platform: 'chatwoot',
      sdkVersion: WAVOIP_SDK_VERSION,
      inboxId,
      wavoipCallId: callId,
      device: buildDeviceSnapshot(inboxId),
      recentIceDiagnostics: iceDiagnostics.slice(-10),
      recentIssues: connectivityIssues.slice(-10),
      recentErrors: callErrors.slice(-10),
      recentStats: callStats.slice(-10),
      browser: {
        userAgent: navigator.userAgent,
        online: navigator.onLine,
      },
    },
    null,
    2
  );
}

export function clearWavoipDiagnostics() {
  iceDiagnostics.length = 0;
  connectivityIssues.length = 0;
  callErrors.length = 0;
  callStats.length = 0;
}
