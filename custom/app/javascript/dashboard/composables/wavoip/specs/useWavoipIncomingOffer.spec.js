import { beforeEach, describe, expect, it, vi } from 'vitest';
import { createPinia, setActivePinia } from 'pinia';
import { useCallsStore } from 'dashboard/stores/calls';

const mockAlert = vi.fn();
const mockTranslate = vi.fn(key => key);
const offerHandlers = {};
const mockClient = {
  on: vi.fn((event, handler) => {
    if (event === 'offer') offerHandlers.offer = handler;
  }),
  off: vi.fn(),
};

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: mockTranslate }),
}));

vi.mock('dashboard/composables', () => ({
  useAlert: (...args) => mockAlert(...args),
}));

vi.mock('vuex', () => ({
  useStore: () => ({
    getters: {
      'inboxes/getInbox': () => null,
    },
  }),
  createStore: vi.fn(() => ({
    getters: {},
    dispatch: vi.fn(),
    commit: vi.fn(),
  })),
}));

vi.mock('customDashboard/composables/wavoip/useWavoipNotifications', () => ({
  notifyIncomingWavoipOffer: vi.fn(),
}));

vi.mock('customDashboard/lib/wavoip/wavoipClientRegistry', () => ({
  getWavoipClient: vi.fn(() => mockClient),
  registerOfferUnsubscriber: vi.fn(),
}));

const { isWavoipSdkCallOwned, getRingingProviderCallId, isOutboundInitiationActive } = vi.hoisted(() => ({
  isWavoipSdkCallOwned: vi.fn(() => false),
  getRingingProviderCallId: vi.fn(() => null),
  isOutboundInitiationActive: vi.fn(() => false),
}));

vi.mock('customDashboard/composables/wavoip/useWavoipActiveCall', () => ({
  isWavoipSdkCallOwned,
  getRingingProviderCallId,
  isOutboundInitiationActive,
}));

import { notifyIncomingWavoipOffer } from 'customDashboard/composables/wavoip/useWavoipNotifications';
import {
  pendingOffers,
  removePendingOffer,
  useWavoipIncomingOffer,
  waitForPendingOffer,
} from '../useWavoipIncomingOffer';
import { VOICE_CALL_DIRECTION } from 'dashboard/components-next/message/constants';

const createOffer = id => {
  const handlers = {};
  return {
    id,
    on: vi.fn((event, handler) => {
      handlers[event] = handler;
    }),
    off: vi.fn(event => {
      delete handlers[event];
    }),
    trigger: event => handlers[event]?.(),
    activeHandlerCount: () => Object.keys(handlers).length,
    accept: vi.fn(),
    reject: vi.fn(),
  };
};

describe('useWavoipIncomingOffer', () => {
  beforeEach(() => {
    pendingOffers.clear();
    offerHandlers.offer = undefined;
    mockAlert.mockClear();
    mockTranslate.mockClear();
    isWavoipSdkCallOwned.mockReset().mockReturnValue(false);
    getRingingProviderCallId.mockReset().mockReturnValue(null);
    isOutboundInitiationActive.mockReset().mockReturnValue(false);
    notifyIncomingWavoipOffer.mockClear();
    setActivePinia(createPinia());
  });

  it('dismisses and alerts on acceptedElsewhere', () => {
    const { attachToInbox } = useWavoipIncomingOffer();
    attachToInbox(1);

    const offer = createOffer('offer_accept_elsewhere');
    offerHandlers.offer(offer);

    const store = useCallsStore();
    expect(store.calls.some(c => c.callSid === offer.id)).toBe(true);

    offer.trigger('acceptedElsewhere');

    expect(mockTranslate).toHaveBeenCalledWith(
      'CONVERSATION.WAVOIP_CALL.ACCEPTED_ELSEWHERE'
    );
    expect(mockAlert).toHaveBeenCalledWith(
      'CONVERSATION.WAVOIP_CALL.ACCEPTED_ELSEWHERE'
    );
    expect(pendingOffers.has(offer.id)).toBe(false);
    expect(store.calls.some(c => c.callSid === offer.id)).toBe(false);
  });

  it('dismisses and alerts on rejectedElsewhere', () => {
    const { attachToInbox } = useWavoipIncomingOffer();
    attachToInbox(2);

    const offer = createOffer('offer_reject_elsewhere');
    offerHandlers.offer(offer);
    offer.trigger('rejectedElsewhere');

    expect(mockTranslate).toHaveBeenCalledWith(
      'CONVERSATION.WAVOIP_CALL.REJECTED_ELSEWHERE'
    );
    expect(mockAlert).toHaveBeenCalledWith(
      'CONVERSATION.WAVOIP_CALL.REJECTED_ELSEWHERE'
    );
    expect(pendingOffers.has(offer.id)).toBe(false);
  });

  it('accepts and rejects pending offers', async () => {
    const { attachToInbox, acceptOffer, rejectOffer } =
      useWavoipIncomingOffer();
    attachToInbox(3);

    const offer = createOffer('offer_actions');
    const activeCall = { id: 'offer_actions', mute: vi.fn(), unmute: vi.fn() };
    offer.accept.mockResolvedValue({ call: activeCall, err: null });
    offerHandlers.offer(offer);

    const call = await acceptOffer(offer.id);
    expect(offer.accept).toHaveBeenCalled();
    expect(call).toBe(activeCall);

    const rejectOfferObj = createOffer('offer_reject');
    offerHandlers.offer(rejectOfferObj);
    await rejectOffer(rejectOfferObj.id);
    expect(rejectOfferObj.reject).toHaveBeenCalled();
    expect(pendingOffers.has(rejectOfferObj.id)).toBe(false);
  });

  it('throws when accept returns err', async () => {
    const { attachToInbox, acceptOffer } = useWavoipIncomingOffer();
    attachToInbox(4);

    const offer = createOffer('offer_err');
    offer.accept.mockResolvedValue({ call: null, err: 'busy' });
    offerHandlers.offer(offer);

    await expect(acceptOffer(offer.id)).rejects.toThrow('busy');
  });

  it('exposes removePendingOffer helper', () => {
    pendingOffers.set('tmp', { offer: { id: 'tmp' }, inboxId: 1 });
    removePendingOffer('tmp');
    expect(pendingOffers.has('tmp')).toBe(false);
  });

  it('rejects waitForPendingOffer when offer is removed', async () => {
    const pending = waitForPendingOffer('call-1');
    removePendingOffer('call-1');
    await expect(pending).rejects.toThrow('Offer cancelled');
  });

  it('ignores SDK offer when agent initiated outbound call', () => {
    const { attachToInbox } = useWavoipIncomingOffer();
    const store = useCallsStore();
    attachToInbox(106);

    store.addCall({
      callSid: 'outbound_sdk',
      inboxId: 106,
      provider: 'wavoip',
      callDirection: VOICE_CALL_DIRECTION.OUTBOUND,
    });

    const offer = createOffer('outbound_sdk');
    offerHandlers.offer(offer);

    expect(store.calls).toHaveLength(1);
    expect(store.calls[0].callDirection).toBe(VOICE_CALL_DIRECTION.OUTBOUND);
    expect(pendingOffers.has(offer.id)).toBe(false);
    expect(notifyIncomingWavoipOffer).not.toHaveBeenCalled();
  });

  it('ignores SDK offer when ringing outbound session owns the id', () => {
    const { attachToInbox } = useWavoipIncomingOffer();
    attachToInbox(107);
    getRingingProviderCallId.mockReturnValue('ringing_out');

    const offer = createOffer('ringing_out');
    offerHandlers.offer(offer);

    expect(useCallsStore().calls).toHaveLength(0);
    expect(pendingOffers.has(offer.id)).toBe(false);
    expect(notifyIncomingWavoipOffer).not.toHaveBeenCalled();
  });

  it('dismisses webhook and SDK rows when caller ends with mismatched ids', () => {
    const { attachToInbox } = useWavoipIncomingOffer();
    const store = useCallsStore();
    attachToInbox(200);

    store.addCall({
      callSid: 'webhook_call_id',
      callId: 22,
      inboxId: 200,
      provider: 'wavoip',
      callDirection: 'incoming',
      awaitingSdkOffer: true,
    });

    const offer = createOffer('sdk_offer_id');
    offerHandlers.offer(offer);
    offer.trigger('ended');

    expect(mockTranslate).toHaveBeenCalledWith(
      'CONVERSATION.WAVOIP_CALL.CALLER_ENDED'
    );
    expect(mockAlert).toHaveBeenCalledWith(
      'CONVERSATION.WAVOIP_CALL.CALLER_ENDED'
    );
    expect(store.calls).toHaveLength(0);
    expect(pendingOffers.has('sdk_offer_id')).toBe(false);
    expect(pendingOffers.has('webhook_call_id')).toBe(false);
  });

  it('unwires all offer listeners once dismissed (no leak)', () => {
    const { attachToInbox } = useWavoipIncomingOffer();
    attachToInbox(300);

    const offer = createOffer('offer_unwire');
    offerHandlers.offer(offer);

    expect(offer.activeHandlerCount()).toBe(4);
    offer.trigger('unanswered');

    expect(offer.off).toHaveBeenCalledTimes(4);
    expect(offer.activeHandlerCount()).toBe(0);
  });

  it('unwires listeners via removePendingOffer even without a terminal SDK event', () => {
    const { attachToInbox } = useWavoipIncomingOffer();
    attachToInbox(301);

    const offer = createOffer('offer_manual_remove');
    offerHandlers.offer(offer);
    expect(offer.activeHandlerCount()).toBe(4);

    removePendingOffer(offer.id);

    expect(offer.off).toHaveBeenCalledTimes(4);
    expect(offer.activeHandlerCount()).toBe(0);
  });
});
