import { useCallsStore } from 'dashboard/stores/calls';
import CallsAPI from 'customDashboard/api/calls';

const pendingAcceptByCallSid = new Set();
const RETRY_DELAYS_MS = [1000, 2000, 4000];
const MAX_ATTEMPTS = 3;

const sleep = ms =>
  new Promise(resolve => {
    setTimeout(resolve, ms);
  });

export function queueAcceptedByRecording(callSid) {
  if (callSid) pendingAcceptByCallSid.add(callSid);
}

export async function recordAcceptWithRetry(dbCallId, callSid, options = {}) {
  const { onFailure } = options;

  for (let attempt = 0; attempt < MAX_ATTEMPTS; attempt += 1) {
    try {
      await CallsAPI.recordAccept(dbCallId);
      return true;
    } catch (_) {
      if (attempt < MAX_ATTEMPTS - 1) {
        await sleep(RETRY_DELAYS_MS[attempt]);
      }
    }
  }

  // eslint-disable-next-line no-console
  console.warn(
    `Failed to record accept for callSid=${callSid} dbCallId=${dbCallId} after ${MAX_ATTEMPTS} attempts`
  );
  onFailure?.();
  return false;
}

export async function flushAcceptedByRecording(callSid, options = {}) {
  if (!pendingAcceptByCallSid.has(callSid)) return;

  const dbCallId = useCallsStore().calls.find(
    c => c.callSid === callSid
  )?.callId;
  if (!dbCallId) return;

  pendingAcceptByCallSid.delete(callSid);
  await recordAcceptWithRetry(dbCallId, callSid, options);
}

export function clearAcceptedByQueue() {
  pendingAcceptByCallSid.clear();
}
