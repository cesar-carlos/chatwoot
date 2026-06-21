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

vi.mock('customDashboard/lib/wavoip/wavoipClientRegistry', () => ({
  getWavoipClient: vi.fn(() => mockClient),
  registerOfferUnsubscriber: vi.fn(),
}));

import {
  pendingOffers,
  removePendingOffer,
  useWavoipIncomingOffer,
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
    offerHandlers.offer(offer);

    await acceptOffer(offer.id);
    expect(offer.accept).toHaveBeenCalled();

    const rejectOfferObj = createOffer('offer_reject');
    offerHandlers.offer(rejectOfferObj);
    await rejectOffer(rejectOfferObj.id);
    expect(rejectOfferObj.reject).toHaveBeenCalled();
    expect(pendingOffers.has(rejectOfferObj.id)).toBe(false);
  });

  it('exposes removePendingOffer helper', () => {
    pendingOffers.set('tmp', { offer: { id: 'tmp' }, inboxId: 1 });
    removePendingOffer('tmp');
    expect(pendingOffers.has('tmp')).toBe(false);
  });
});
