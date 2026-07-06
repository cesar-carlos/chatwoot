import { useCallsStore } from 'dashboard/stores/calls';
import { markCallDismissed } from 'dashboard/composables/useCallSession';
import { removePendingOffer } from 'customDashboard/composables/wavoip/useWavoipIncomingOffer';

const collectWavoipCallIds = (callsStore, callIds) => {
  const ids = new Set(callIds.filter(Boolean));

  callsStore.calls.forEach(call => {
    const matches =
      ids.has(call.callSid) ||
      ids.has(call.wavoipOfferId) ||
      (call.callId != null && ids.has(String(call.callId)));
    if (!matches) return;

    ids.add(call.callSid);
    if (call.wavoipOfferId) ids.add(call.wavoipOfferId);
    if (call.callId != null) ids.add(String(call.callId));
  });

  return ids;
};

/** Remove Wavoip rows from the calls store (and pending offers) by any known id. */
export function removeWavoipCallFromStore(...callIds) {
  const callsStore = useCallsStore();
  const ids = collectWavoipCallIds(callsStore, callIds);

  ids.forEach(callSid => {
    removePendingOffer(callSid);
    callsStore.removeCall(callSid);
  });
}

/** Dismiss ringing Wavoip widgets on other agents' tabs (no SDK teardown). */
export function dismissWavoipCallFromStore(...callIds) {
  const callsStore = useCallsStore();
  const ids = collectWavoipCallIds(callsStore, callIds);

  ids.forEach(callSid => {
    removePendingOffer(callSid);
    markCallDismissed(callSid);
    callsStore.dismissCall(callSid);
  });
}
