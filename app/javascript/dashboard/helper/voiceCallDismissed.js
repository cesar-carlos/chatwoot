import { addToCappedSet } from 'customDashboard/lib/voice/cappedSet';

// Leaf module: dismissed call sids must not live in useCallSession or helper/voice.
// Those files import Wavoip teardown/cable, which used to import back and hit TDZ
// ("Cannot access '…' before initialization") in the production bundle.

const dismissedCallSids = new Set();

export const markCallDismissed = callSid => {
  addToCappedSet(dismissedCallSids, callSid);
};

export const isCallDismissed = callSid =>
  callSid ? dismissedCallSids.has(callSid) : false;
