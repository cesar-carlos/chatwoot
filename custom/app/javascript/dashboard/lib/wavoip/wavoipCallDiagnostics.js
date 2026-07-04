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
  if (!call?.on) return () => {};

  const handlers = {
    iceDiagnostics: payload => {
      recordIceDiagnostics(inboxId, callId, payload);
    },
    connectivityIssue: issue => {
      recordConnectivityIssue(inboxId, callId, issue);
      if (shouldShowConnectivityAlert(callId)) {
        useAlert(connectivityMessage(issue, translateFn));
      }
    },
    error: error => {
      recordCallError(inboxId, callId, error);
    },
    stats: stats => {
      recordCallStats(inboxId, callId, stats);
    },
    serverStats: stats => {
      recordCallStats(inboxId, callId, { server: stats });
    },
  };

  call.on('iceDiagnostics', handlers.iceDiagnostics);
  call.on('connectivityIssue', handlers.connectivityIssue);
  call.on('error', handlers.error);
  call.on('stats', handlers.stats);
  call.on('serverStats', handlers.serverStats);

  return () => {
    call.off?.('iceDiagnostics', handlers.iceDiagnostics);
    call.off?.('connectivityIssue', handlers.connectivityIssue);
    call.off?.('error', handlers.error);
    call.off?.('stats', handlers.stats);
    call.off?.('serverStats', handlers.serverStats);
  };
};

const unwireCallDiagnostics = unwire => {
  unwire?.();
};

export { wireCallDiagnostics, unwireCallDiagnostics };
