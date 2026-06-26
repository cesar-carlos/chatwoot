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

async function recordAcceptWithRetry(dbCallId, callSid, attempt = 0) {
  try {
    await CallsAPI.recordAccept(dbCallId);
    return undefined;
  } catch (_) {
    if (attempt < MAX_ATTEMPTS - 1) {
      await sleep(RETRY_DELAYS_MS[attempt]);
      return recordAcceptWithRetry(dbCallId, callSid, attempt + 1);
    }

    // eslint-disable-next-line no-console
    console.warn(
      `Failed to record accept for callSid=${callSid} dbCallId=${dbCallId} after ${MAX_ATTEMPTS} attempts`
    );
    return undefined;
  }
}

export async function flushAcceptedByRecording(callSid) {
  if (!pendingAcceptByCallSid.has(callSid)) return;

  const dbCallId = useCallsStore().calls.find(
    c => c.callSid === callSid
  )?.callId;
  if (!dbCallId) return;

  pendingAcceptByCallSid.delete(callSid);
  await recordAcceptWithRetry(dbCallId, callSid);
}

export function clearAcceptedByQueue() {
  pendingAcceptByCallSid.clear();
}
