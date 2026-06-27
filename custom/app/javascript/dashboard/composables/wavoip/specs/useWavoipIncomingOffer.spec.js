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

import {
  pendingOffers,
  removePendingOffer,
  useWavoipIncomingOffer,
  waitForPendingOffer,
} from '../useWavoipIncomingOffer';

const createOffer = id => {
  const handlers = {};
  return {
    id,
    on: vi.fn((event, handler) => {
      handlers[event] = handler;
    }),
    trigger: event => handlers[event]?.(),
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

  it('dismisses webhook and SDK rows when caller ends with mismatched ids', () => {
    const { attachToInbox } = useWavoipIncomingOffer();
    const store = useCallsStore();
    attachToInbox(106);

    store.addCall({
      callSid: 'webhook_call_id',
      callId: 22,
      inboxId: 106,
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
});
