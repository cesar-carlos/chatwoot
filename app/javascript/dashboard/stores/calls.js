import TwilioVoiceClient from 'dashboard/api/channel/voice/twilioVoiceClient';
import { isBrowserVoiceProvider } from 'customDashboard/lib/voice/browserVoiceProviders';
import { teardownBrowserVoiceSession } from 'customDashboard/lib/voice/voiceSessionRegistry';
import { TERMINAL_STATUSES } from 'dashboard/helper/voice';
import { VOICE_CALL_PROVIDERS } from 'dashboard/helper/inbox';
import { isWavoipSdkCallOwned } from 'customDashboard/composables/wavoip/useWavoipActiveCall';
import { defineStore } from 'pinia';

const teardownByProvider = call => {
  if (isBrowserVoiceProvider(call?.provider)) {
    teardownBrowserVoiceSession(call.provider);
    return;
  }
  TwilioVoiceClient.endClientCall();
};

export const useCallsStore = defineStore('calls', {
  state: () => ({
    calls: [],
  }),

  getters: {
    activeCall: state => state.calls.find(call => call.isActive) || null,
    hasActiveCall: state => state.calls.some(call => call.isActive),
    incomingCalls: state => state.calls.filter(call => !call.isActive),
    hasIncomingCall: state => state.calls.some(call => !call.isActive),
  },

  actions: {
    handleCallStatusChanged({ callSid, status }) {
      if (!TERMINAL_STATUSES.includes(status)) return;

      const call = this.calls.find(c => c.callSid === callSid);
      // WhatsApp recordings live in the in-memory recorder until voice_call.ended
      // uploads them; tearing down here would race-wipe those chunks.
      if (call?.provider === VOICE_CALL_PROVIDERS.WHATSAPP) {
        this.calls = this.calls.filter(c => c.callSid !== callSid);
        return;
      }

      if (
        call?.provider === VOICE_CALL_PROVIDERS.WAVOIP &&
        call?.callDirection === 'outbound' &&
        isWavoipSdkCallOwned(callSid)
      ) {
        return;
      }

      this.removeCall(callSid);
    },

    addCall(callData) {
      if (!callData?.callSid) return;
      // Wavoip's webhook call_id and the SDK's Offer.id can diverge; match by
      // those alias ids too so a race between the two paths merges into one
      // row instead of leaving two widgets until something else reconciles
      // them later.
      const existing = this.calls.find(
        c =>
          c.callSid === callData.callSid ||
          (callData.wavoipOfferId &&
            c.wavoipOfferId === callData.wavoipOfferId) ||
          (callData.callId != null && c.callId === callData.callId)
      );
      if (existing) {
        // Merge so a later cable event with sdp_offer/provider/caller fills in
        // gaps left by the earlier message.created path (and vice versa).
        // Preserve a previously-captured caller snapshot when the incoming
        // event has no sender info, otherwise the widget would flip to
        // "Unknown caller" on the next status update.
        const next = { ...callData };
        if (existing.caller && !next.caller) delete next.caller;
        // Keep the existing callSid as canonical when this match came through
        // an alias id rather than an exact callSid match — otherwise the
        // entry's key would shift under callers still tracking the old sid
        // (active call widget, dismiss/accept flows).
        if (existing.callSid !== callData.callSid) delete next.callSid;
        Object.assign(existing, next, { isActive: existing.isActive });
        return;
      }

      // Prepend so the newest call surfaces as the primary card (incomingCalls[0])
      // and older calls drop into the stack below it.
      this.calls.unshift({
        ...callData,
        isActive: false,
      });
    },

    removeCall(callSid) {
      const callToRemove = this.calls.find(c => c.callSid === callSid);
      if (callToRemove?.isActive) {
        teardownByProvider(callToRemove);
      }
      this.calls = this.calls.filter(c => c.callSid !== callSid);
    },

    setCallActive(callSid) {
      this.calls = this.calls.map(call => ({
        ...call,
        isActive: call.callSid === callSid,
      }));
    },

    clearActiveCall() {
      const active = this.calls.find(c => c.isActive);
      teardownByProvider(active);
      this.calls = this.calls.filter(call => !call.isActive);
    },

    dismissCall(callSid) {
      this.calls = this.calls.filter(call => call.callSid !== callSid);
    },

    removeCallsForConversation(conversationId) {
      const callsToRemove = this.calls.filter(
        call => call.conversationId === conversationId
      );

      // Tear down each active call via its own provider so a WhatsApp call
      // gets cleanupWhatsappSession() (closes pc, stops recorder/mic) instead
      // of the Twilio-only endClientCall() — otherwise mic stays open.
      callsToRemove.filter(call => call.isActive).forEach(teardownByProvider);

      this.calls = this.calls.filter(
        call => call.conversationId !== conversationId
      );
    },
  },
});
