import {
  recordCallError,
  recordConnectivityIssue,
  recordIceDiagnostics,
  recordCallStats,
} from 'customDashboard/lib/wavoip/wavoipDiagnosticsCollector';
import { useAlert } from 'dashboard/composables';

const CONNECTIVITY_DEBOUNCE_MS = 5000;
const lastConnectivityAlertAt = new Map();

const connectivityMessage = (issue, translateFn) => {
  const code = issue?.code || issue?.type || issue || 'GENERIC';
  if (translateFn) {
    return translateFn(`CONVERSATION.WAVOIP_CONNECTIVITY.${code}`);
  }
  return 'Call connection issue';
};

const shouldShowConnectivityAlert = callId => {
  const key = callId || 'global';
  const now = Date.now();
  const last = lastConnectivityAlertAt.get(key) || 0;
  if (now - last < CONNECTIVITY_DEBOUNCE_MS) return false;
  lastConnectivityAlertAt.set(key, now);
  return true;
};

const wireCallDiagnostics = (call, { inboxId, callId, translateFn } = {}) => {
  if (!call?.on) return;

  call.on('iceDiagnostics', payload => {
    recordIceDiagnostics(inboxId, callId, payload);
  });
  call.on('connectivityIssue', issue => {
    recordConnectivityIssue(inboxId, callId, issue);
    if (shouldShowConnectivityAlert(callId)) {
      useAlert(connectivityMessage(issue, translateFn));
    }
  });
  call.on('error', error => {
    recordCallError(inboxId, callId, error);
  });
  call.on('stats', stats => {
    recordCallStats(inboxId, callId, stats);
  });
  call.on('serverStats', stats => {
    recordCallStats(inboxId, callId, { server: stats });
  });
};

export { wireCallDiagnostics };
