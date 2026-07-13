import { beforeEach, describe, expect, it, vi } from 'vitest';
import { createPinia, setActivePinia } from 'pinia';
import { VOICE_CALL_PROVIDERS } from 'dashboard/helper/inbox';
import { VOICE_CALL_DIRECTION } from 'dashboard/components-next/message/constants';

const acceptIncomingCallMock = vi.fn();
const rejectIncomingCallMock = vi.fn();
const connectForInboxMock = vi.fn();
const teardownWavoipActiveCallMock = vi.fn();
const removePendingOfferMock = vi.fn();

vi.mock('customDashboard/lib/voice/voiceSessionRegistry', async () => {
  const actual = await vi.importActual(
    'customDashboard/lib/voice/voiceSessionRegistry'
  );
  return {
    ...actual,
    getBrowserVoiceSession: () => ({
      connectForInbox: connectForInboxMock,
      acceptIncomingCall: acceptIncomingCallMock,
      rejectIncomingCall: rejectIncomingCallMock,
    }),
    teardownWavoipActiveCall: () => teardownWavoipActiveCallMock(),
    cleanupAfterBrowserVoiceJoinFailure: (call, callSid) => {
      if (call?.provider === 'wavoip') {
        teardownWavoipActiveCallMock();
        removePendingOfferMock(callSid);
        return false;
      }
      return false;
    },
  };
});

vi.mock('customDashboard/composables/wavoip/useWavoipIncomingOffer', () => ({
  removePendingOffer: (...args) => removePendingOfferMock(...args),
}));

vi.mock('customDashboard/composables/wavoip/useWavoipNotifications', () => ({
  isWavoipInboxRestricted: () => false,
}));

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/composables/useWhatsappCallSession', () => ({
  useWhatsappCallSession: () => ({}),
  sendWhatsappTerminateBeacon: vi.fn(),
  cleanupWhatsappSession: vi.fn(),
}));
vi.mock('dashboard/api/channel/voice/twilioVoiceClient', () => ({
  default: {
    initializeDevice: vi.fn(),
    joinClientCall: vi.fn(),
    endClientCall: vi.fn(),
    addEventListener: vi.fn(),
    removeEventListener: vi.fn(),
  },
}));
vi.mock('dashboard/api/channel/voice/voiceAPIClient', () => ({
  default: { joinConference: vi.fn(), leaveConference: vi.fn() },
}));

import { useCallActions } from '../useCallSession';
import { useCallsStore } from 'dashboard/stores/calls';

describe('useCallSession Wavoip actions', () => {
  beforeEach(() => {
    setActivePinia(createPinia());
    acceptIncomingCallMock.mockReset();
    rejectIncomingCallMock.mockReset();
    connectForInboxMock.mockReset();
    teardownWavoipActiveCallMock.mockReset();
    removePendingOfferMock.mockReset();
    rejectIncomingCallMock.mockResolvedValue(undefined);
    connectForInboxMock.mockResolvedValue(undefined);
  });

  it('keeps the ringing card on Wavoip join failure so the agent can retry', async () => {
    acceptIncomingCallMock.mockRejectedValue(new Error('accept failed'));
    const store = useCallsStore();
    store.addCall({
      callSid: 'join_fail_1',
      inboxId: 5,
      conversationId: 1,
      provider: VOICE_CALL_PROVIDERS.WAVOIP,
      callDirection: VOICE_CALL_DIRECTION.INCOMING,
    });

    const { joinCall } = useCallActions();
    await joinCall({ conversationId: 1, inboxId: 5, callSid: 'join_fail_1' });

    expect(teardownWavoipActiveCallMock).toHaveBeenCalled();
    expect(removePendingOfferMock).toHaveBeenCalledWith('join_fail_1');
    expect(store.calls.some(c => c.callSid === 'join_fail_1')).toBe(true);
  });

  it('surfaces Wavoip i18nKey alerts on join failure', async () => {
    const { useAlert } = await import('dashboard/composables');
    acceptIncomingCallMock.mockRejectedValue(
      Object.assign(new Error('disconnected'), {
        i18nKey: 'CONVERSATION.WAVOIP_CALL.DEVICE_DISCONNECTED',
      })
    );
    const store = useCallsStore();
    store.addCall({
      callSid: 'join_fail_i18n',
      inboxId: 5,
      conversationId: 1,
      provider: VOICE_CALL_PROVIDERS.WAVOIP,
      callDirection: VOICE_CALL_DIRECTION.INCOMING,
    });

    const { joinCall } = useCallActions();
    await joinCall({
      conversationId: 1,
      inboxId: 5,
      callSid: 'join_fail_i18n',
    });

    expect(useAlert).toHaveBeenCalledWith(
      'CONVERSATION.WAVOIP_CALL.DEVICE_DISCONNECTED'
    );
  });

  it('routes Wavoip inbound dismiss through SDK reject with store cleanup', async () => {
    const store = useCallsStore();
    store.addCall({
      callSid: 'dismiss_1',
      inboxId: 5,
      conversationId: 1,
      provider: VOICE_CALL_PROVIDERS.WAVOIP,
      callDirection: VOICE_CALL_DIRECTION.INBOUND,
      isActive: false,
    });

    const { dismissCall } = useCallActions();
    await dismissCall('dismiss_1');

    expect(rejectIncomingCallMock).toHaveBeenCalledWith('dismiss_1');
    expect(store.calls.some(c => c.callSid === 'dismiss_1')).toBe(false);
  });

  it('routes legacy incoming direction through SDK reject', async () => {
    const store = useCallsStore();
    store.addCall({
      callSid: 'dismiss_2',
      inboxId: 5,
      conversationId: 1,
      provider: VOICE_CALL_PROVIDERS.WAVOIP,
      callDirection: VOICE_CALL_DIRECTION.INCOMING,
      isActive: false,
    });

    const { dismissCall } = useCallActions();
    await dismissCall('dismiss_2');

    expect(rejectIncomingCallMock).toHaveBeenCalledWith('dismiss_2');
    expect(store.calls.some(c => c.callSid === 'dismiss_2')).toBe(false);
  });
});
