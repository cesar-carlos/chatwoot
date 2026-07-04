import { useCallsStore } from 'dashboard/stores/calls';
import { removePendingOffer } from 'customDashboard/composables/wavoip/useWavoipIncomingOffer';

/** Remove Wavoip rows from the calls store (and pending offers) by any known id. */
export function removeWavoipCallFromStore(...callIds) {
  const callsStore = useCallsStore();
  const ids = new Set(callIds.filter(Boolean));

  callsStore.calls.forEach(call => {
    if (ids.has(call.callSid) || ids.has(call.wavoipOfferId)) {
      ids.add(call.callSid);
      if (call.wavoipOfferId) ids.add(call.wavoipOfferId);
    }
  });

  ids.forEach(callSid => {
    removePendingOffer(callSid);
    callsStore.removeCall(callSid);
  });
}
