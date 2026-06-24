import { beforeEach, describe, expect, it, vi } from 'vitest';
import { createPinia, setActivePinia } from 'pinia';
import { VOICE_CALL_PROVIDERS } from 'dashboard/helper/inbox';
import { VOICE_CALL_DIRECTION } from 'dashboard/components-next/message/constants';
import {
  getBrowserVoiceSession,
  registerWavoipCallSession,
} from 'customDashboard/lib/voice/voiceSessionRegistry';

const acceptIncomingCallMock = vi.fn();
const rejectIncomingCallMock = vi.fn();
const connectForInboxMock = vi.fn();

vi.mock('customDashboard/composables/wavoip/useWavoipIncomingOffer', () => ({
  removePendingOffer: vi.fn(),
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

describe('useCallSession Wavoip registry integration', () => {
  beforeEach(() => {
    setActivePinia(createPinia());
    acceptIncomingCallMock.mockReset();
    rejectIncomingCallMock.mockReset();
    connectForInboxMock.mockReset();
    acceptIncomingCallMock.mockResolvedValue({});
    rejectIncomingCallMock.mockResolvedValue(undefined);
    connectForInboxMock.mockResolvedValue(undefined);

    registerWavoipCallSession({
      connectForInbox: connectForInboxMock,
      acceptIncomingCall: acceptIncomingCallMock,
      rejectIncomingCall: rejectIncomingCallMock,
    });
  });

  it('joinCall resolves the pre-registered Wavoip session singleton', async () => {
    const store = useCallsStore();
    store.addCall({
      callSid: 'reg_join_1',
      inboxId: 5,
      conversationId: 1,
      provider: VOICE_CALL_PROVIDERS.WAVOIP,
      callDirection: VOICE_CALL_DIRECTION.INCOMING,
    });

    const { joinCall } = useCallActions();
    await joinCall({ conversationId: 1, inboxId: 5, callSid: 'reg_join_1' });

    expect(getBrowserVoiceSession(VOICE_CALL_PROVIDERS.WAVOIP)).toBeTruthy();
    expect(connectForInboxMock).toHaveBeenCalledWith(5);
    expect(acceptIncomingCallMock).toHaveBeenCalledWith({
      callId: 'reg_join_1',
      inboxId: 5,
      conversationId: 1,
    });
    expect(store.calls.find(c => c.callSid === 'reg_join_1')?.isActive).toBe(true);
  });

  it('rejectIncomingCall uses the pre-registered Wavoip session singleton', async () => {
    const store = useCallsStore();
    store.addCall({
      callSid: 'reg_reject_1',
      inboxId: 5,
      conversationId: 1,
      provider: VOICE_CALL_PROVIDERS.WAVOIP,
      callDirection: VOICE_CALL_DIRECTION.INCOMING,
    });

    const { rejectIncomingCall } = useCallActions();
    await rejectIncomingCall('reg_reject_1');

    expect(rejectIncomingCallMock).toHaveBeenCalledWith('reg_reject_1');
    expect(store.calls.some(c => c.callSid === 'reg_reject_1')).toBe(false);
  });
});
