import {
  recordCallError,
  recordConnectivityIssue,
  recordIceDiagnostics,
  recordCallStats,
} from 'customDashboard/lib/wavoip/wavoipDiagnosticsCollector';
import { useAlert } from 'dashboard/composables';

const CONNECTIVITY_DEBOUNCE_MS = 5000;
const STATS_POLL_MS = 2000;
const lastConnectivityAlertAt = new Map();

const connectivityMessage = (issue, translateFn) => {
  const code = issue?.code || issue?.type || issue || 'GENERIC';
  if (translateFn) {
    const key = `CONVERSATION.WAVOIP_CONNECTIVITY.${code}`;
    const message = translateFn(key);
    if (message === key) {
      return translateFn('CONVERSATION.WAVOIP_CONNECTIVITY.GENERIC');
    }
    return message;
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
  };

  call.on('iceDiagnostics', handlers.iceDiagnostics);
  call.on('connectivityIssue', handlers.connectivityIssue);
  call.on('error', handlers.error);

  // Pull stats on our cadence. The SDK `stats` / `serverStats` events tick
  // every 200ms and are deprecated (console.warn on first subscribe).
  let statsTimer;
  if (typeof call.getStats === 'function') {
    statsTimer = setInterval(async () => {
      try {
        recordCallStats(inboxId, callId, await call.getStats());
      } catch (_) {
        /* snapshot is best-effort */
      }
    }, STATS_POLL_MS);
  }

  return () => {
    clearInterval(statsTimer);
    call.off?.('iceDiagnostics', handlers.iceDiagnostics);
    call.off?.('connectivityIssue', handlers.connectivityIssue);
    call.off?.('error', handlers.error);
  };
};

const unwireCallDiagnostics = unwire => {
  unwire?.();
};

export { wireCallDiagnostics, unwireCallDiagnostics };
