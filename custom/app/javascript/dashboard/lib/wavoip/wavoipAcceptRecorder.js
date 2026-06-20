import { useCallsStore } from 'dashboard/stores/calls';
import CallsAPI from 'customDashboard/api/calls';

const pendingAcceptByCallSid = new Set();

export function queueAcceptedByRecording(callSid) {
  if (callSid) pendingAcceptByCallSid.add(callSid);
}

export async function flushAcceptedByRecording(callSid) {
  if (!pendingAcceptByCallSid.has(callSid)) return;

  const dbCallId = useCallsStore().calls.find(
    c => c.callSid === callSid
  )?.callId;
  if (!dbCallId) return;

  pendingAcceptByCallSid.delete(callSid);
  try {
    await CallsAPI.recordAccept(dbCallId);
  } catch (_) {
    pendingAcceptByCallSid.add(callSid);
  }
}

export function clearAcceptedByQueue() {
  pendingAcceptByCallSid.clear();
}
