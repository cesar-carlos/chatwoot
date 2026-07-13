import { beforeEach, describe, expect, it, vi } from 'vitest';
import { createPinia, setActivePinia } from 'pinia';
import { useCallsStore } from 'dashboard/stores/calls';
import { VOICE_CALL_PROVIDERS } from 'dashboard/helper/inbox';

const connectForInbox = vi.fn();
const ensureDeviceReadiness = vi.fn();
const getWavoipClientEntry = vi.fn();

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: key => key,
  }),
}));

vi.mock('customDashboard/composables/wavoip/useWavoipConnection', () => ({
  useWavoipConnection: () => ({
    connectForInbox,
    ensureDeviceReadiness,
  }),
}));

vi.mock('customDashboard/lib/wavoip/wavoipClientRegistry', () => ({
  getWavoipClientEntry: (...args) => getWavoipClientEntry(...args),
}));

vi.mock('customDashboard/composables/wavoip/useWavoipActiveCall', () => ({
  setActiveCall: vi.fn(),
  setRingingOutgoingCall: vi.fn(),
  clearRingingOutgoingCall: vi.fn(),
  beginOutboundInitiation: vi.fn(),
  endOutboundInitiation: vi.fn(),
}));

const wavoipOutboundBlockedReasonKey = vi.fn(() => null);
vi.mock('customDashboard/lib/wavoip/wavoipOutboundPreflight', () => ({
  wavoipOutboundBlockedReasonKey: (...args) =>
    wavoipOutboundBlockedReasonKey(...args),
}));

vi.mock('customDashboard/lib/wavoip/wavoipOutboundRingback', () => ({
  unlockWavoipOutboundRingback: vi.fn(),
  startWavoipOutboundRingback: vi.fn(),
  stopWavoipOutboundRingback: vi.fn(),
}));

vi.mock('dashboard/composables/useCallRingtonePreference', () => ({
  useCallRingtonePreference: () => ({
    isRingtoneMuted: { value: false },
    initPreference: vi.fn(),
    toggleRingtoneMute: vi.fn(),
  }),
}));

const toggleStatus = vi.fn().mockResolvedValue({
  data: { payload: { current_status: 'open' } },
});
const dispatch = vi.fn((action, payload) => {
  if (action === 'toggleStatus') return toggleStatus(payload);
  return Promise.resolve();
});

vi.mock('vuex', () => ({
  useStore: () => ({
    getters: {
      getConversationById: () => () => ({ id: 42, status: 'resolved' }),
    },
    dispatch,
  }),
  createStore: vi.fn(() => ({
    getters: {},
    dispatch: vi.fn(),
    commit: vi.fn(),
  })),
}));

const createOutgoingCall = id => {
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
  };
};

describe('useWavoipOutboundCall', () => {
  let useWavoipOutboundCall;

  beforeEach(async () => {
    vi.resetModules();
    connectForInbox.mockReset();
    ensureDeviceReadiness.mockReset();
    getWavoipClientEntry.mockReset();
    wavoipOutboundBlockedReasonKey.mockReset().mockReturnValue(null);
    setActivePinia(createPinia());
    ({ useWavoipOutboundCall } = await import('../useWavoipOutboundCall'));
  });

  it('starts an outbound call and adds it to the store', async () => {
    const outgoingCall = createOutgoingCall('out_001');
    const client = {
      startCall: vi.fn().mockResolvedValue({ call: outgoingCall, err: null }),
    };

    connectForInbox.mockResolvedValue(client);
    ensureDeviceReadiness.mockResolvedValue({ ready: true, status: 'open' });
    getWavoipClientEntry.mockReturnValue({ token: 'device-token' });

    const { initiateOutboundCall } = useWavoipOutboundCall();
    const result = await initiateOutboundCall(42, {
      inboxId: 7,
      toPhone: '+15551234567',
    });

    expect(client.startCall).toHaveBeenCalledWith({
      to: '+15551234567',
      fromTokens: ['device-token'],
    });
    expect(result).toEqual({
      id: null,
      call_id: 'out_001',
      status: 'started',
    });

    const store = useCallsStore();
    expect(store.calls[0]).toMatchObject({
      callSid: 'out_001',
      conversationId: 42,
      inboxId: 7,
      provider: VOICE_CALL_PROVIDERS.WAVOIP,
    });
    expect(toggleStatus).toHaveBeenCalledWith(
      expect.objectContaining({
        conversationId: 42,
        status: 'open',
      })
    );
  });

  it('returns locked when a call is already initiating', async () => {
    let finishStart;
    const client = {
      startCall: vi.fn(
        () =>
          new Promise(resolve => {
            finishStart = () =>
              resolve({ call: createOutgoingCall('out_locked'), err: null });
          })
      ),
    };

    connectForInbox.mockResolvedValue(client);
    ensureDeviceReadiness.mockResolvedValue({ ready: true, status: 'open' });
    getWavoipClientEntry.mockReturnValue({ token: 'device-token' });

    const { initiateOutboundCall } = useWavoipOutboundCall();
    const first = initiateOutboundCall(1, {
      inboxId: 2,
      toPhone: '+15550001111',
    });
    await Promise.resolve();
    const second = await initiateOutboundCall(1, {
      inboxId: 2,
      toPhone: '+15550001111',
    });

    expect(second).toEqual({ status: 'locked' });
    finishStart();
    await first;
  });

  it('unwraps legacy startCall return shape (bare CallOutgoing)', async () => {
    const outgoingCall = createOutgoingCall('out_legacy');
    outgoingCall.end = vi.fn();
    const client = {
      startCall: vi.fn().mockResolvedValue(outgoingCall),
    };

    connectForInbox.mockResolvedValue(client);
    ensureDeviceReadiness.mockResolvedValue({ ready: true, status: 'open' });
    getWavoipClientEntry.mockReturnValue({ token: 'device-token' });

    const { initiateOutboundCall } = useWavoipOutboundCall();
    const result = await initiateOutboundCall(99, {
      inboxId: 3,
      toPhone: '+5566999050312',
    });

    expect(result.call_id).toBe('out_legacy');
    expect(useCallsStore().calls[0]?.callSid).toBe('out_legacy');
  });

  it('throws when the client cannot be created', async () => {
    connectForInbox.mockResolvedValue(null);

    const { initiateOutboundCall } = useWavoipOutboundCall();

    await expect(
      initiateOutboundCall(1, { inboxId: 2, toPhone: '+15550001111' })
    ).rejects.toThrow('CONVERSATION.WAVOIP_CALL.CLIENT_UNAVAILABLE');
  });

  it('fails fast with a specific message when the device is restricted/full', async () => {
    wavoipOutboundBlockedReasonKey.mockReturnValue(
      'CONVERSATION.WAVOIP_CALL.CHANNELS_FULL'
    );

    const { initiateOutboundCall } = useWavoipOutboundCall();

    await expect(
      initiateOutboundCall(1, { inboxId: 2, toPhone: '+15550001111' })
    ).rejects.toThrow('CONVERSATION.WAVOIP_CALL.CHANNELS_FULL');
    expect(connectForInbox).not.toHaveBeenCalled();
  });

  it('translates a raw SDK connect failure into a specific message', async () => {
    connectForInbox.mockRejectedValue(new Error('websocket closed'));

    const { initiateOutboundCall } = useWavoipOutboundCall();

    await expect(
      initiateOutboundCall(1, { inboxId: 2, toPhone: '+15550001111' })
    ).rejects.toThrow('CONVERSATION.WAVOIP_CALL.CONNECT_FAILED');
  });

  it('unwires all SDK listeners once a terminal event fires (no leak)', async () => {
    const outgoingCall = createOutgoingCall('out_unwire');
    const client = {
      startCall: vi.fn().mockResolvedValue({ call: outgoingCall, err: null }),
    };

    connectForInbox.mockResolvedValue(client);
    ensureDeviceReadiness.mockResolvedValue({ ready: true, status: 'open' });
    getWavoipClientEntry.mockReturnValue({ token: 'device-token' });

    const { initiateOutboundCall } = useWavoipOutboundCall();
    await initiateOutboundCall(1, { inboxId: 2, toPhone: '+15550001111' });

    expect(outgoingCall.activeHandlerCount()).toBe(4);
    outgoingCall.trigger('ended');

    expect(outgoingCall.off).toHaveBeenCalledTimes(4);
    expect(outgoingCall.activeHandlerCount()).toBe(0);
  });
});
