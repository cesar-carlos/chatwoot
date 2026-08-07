import { useCallsStore } from 'dashboard/stores/calls';
import { useAlert } from 'dashboard/composables';
import CallsAPI from 'customDashboard/api/calls';

const pendingAcceptByCallSid = new Set();
const RETRY_DELAYS_MS = [1000, 2000, 4000];
const MAX_ATTEMPTS = 3;
const ACCEPT_RECORD_FAILED_KEY =
  'CONVERSATION.WAVOIP_CALL.ACCEPT_RECORD_FAILED';

const sleep = ms =>
  new Promise(resolve => {
    setTimeout(resolve, ms);
  });

const resolveFailureHandler = options => {
  if (options.onFailure) return options.onFailure;
  if (options.t) {
    return () => useAlert(options.t(ACCEPT_RECORD_FAILED_KEY));
  }
  return undefined;
};

const findDbCallId = callSid => {
  if (!callSid) return null;
  return (
    useCallsStore().calls.find(
      c => c.callSid === callSid || c.wavoipOfferId === callSid
    )?.callId || null
  );
};

const httpStatus = error =>
  error?.response?.status || error?.status || error?.statusCode || null;

/** 409 CallAlreadyAccepted — do not retry; another agent owns the claim. */
export const isAcceptConflictError = error => httpStatus(error) === 409;

export function queueAcceptedByRecording(callSid) {
  if (callSid) pendingAcceptByCallSid.add(callSid);
}

export async function recordJoinWithRetry(dbCallId, callSid, options = {}) {
  const onFailure = resolveFailureHandler(options);
  const onConflict = options.onConflict;

  const attemptJoin = async attempt => {
    try {
      await CallsAPI.joinCall(dbCallId);
      return { ok: true };
    } catch (error) {
      if (isAcceptConflictError(error)) {
        return { conflict: true, error };
      }
      if (attempt >= MAX_ATTEMPTS - 1) return { ok: false, error };
      await sleep(RETRY_DELAYS_MS[attempt]);
      return attemptJoin(attempt + 1);
    }
  };

  const result = await attemptJoin(0);
  if (result.ok) return true;

  if (result.conflict) {
    // eslint-disable-next-line no-console
    console.warn(
      `Join conflict for callSid=${callSid} dbCallId=${dbCallId} — call already accepted`
    );
    onConflict?.(result.error);
    return false;
  }

  // eslint-disable-next-line no-console
  console.warn(
    `Failed to record join intent for callSid=${callSid} dbCallId=${dbCallId} after ${MAX_ATTEMPTS} attempts`
  );
  onFailure?.(result.error);
  return false;
}

export async function recordAcceptWithRetry(dbCallId, callSid, options = {}) {
  const onFailure = resolveFailureHandler(options);
  const onConflict = options.onConflict;

  const attemptRecord = async attempt => {
    try {
      await CallsAPI.recordAccept(dbCallId);
      return { ok: true };
    } catch (error) {
      if (isAcceptConflictError(error)) {
        return { conflict: true, error };
      }
      if (attempt >= MAX_ATTEMPTS - 1) return { ok: false, error };
      await sleep(RETRY_DELAYS_MS[attempt]);
      return attemptRecord(attempt + 1);
    }
  };

  const result = await attemptRecord(0);
  if (result.ok) return true;

  if (result.conflict) {
    // eslint-disable-next-line no-console
    console.warn(
      `Accept conflict for callSid=${callSid} dbCallId=${dbCallId} — call already accepted`
    );
    onConflict?.(result.error);
    return false;
  }

  // eslint-disable-next-line no-console
  console.warn(
    `Failed to record accept for callSid=${callSid} dbCallId=${dbCallId} after ${MAX_ATTEMPTS} attempts`
  );
  onFailure?.(result.error);
  return false;
}

export async function flushAcceptedByRecording(callSid, options = {}) {
  if (!pendingAcceptByCallSid.has(callSid)) return;

  const dbCallId = findDbCallId(callSid);
  if (!dbCallId) return;

  pendingAcceptByCallSid.delete(callSid);
  const joined = await recordJoinWithRetry(dbCallId, callSid, options);
  if (!joined) return;
  await recordAcceptWithRetry(dbCallId, callSid, options);
}

export function clearAcceptedByQueue() {
  pendingAcceptByCallSid.clear();
}
