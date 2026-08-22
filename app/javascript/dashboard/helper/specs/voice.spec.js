import { beforeEach, describe, expect, it, vi } from 'vitest';
import { setActivePinia, createPinia } from 'pinia';
import { VOICE_CALL_PROVIDERS } from 'dashboard/helper/inbox';

vi.mock('customDashboard/lib/wavoip/wavoipInboxCallRouting', () => ({
  shouldReceiveWavoipInboundRing: vi.fn(() => true),
}));

vi.mock('customDashboard/composables/wavoip/useWavoipActiveCall', () => ({
  isOutboundInitiationActive: vi.fn(() => false),
  isWavoipSdkCallOwned: vi.fn(() => false),
}));

vi.mock('dashboard/store', () => ({
  default: {
    getters: {
      'inboxes/getInbox': vi.fn(() => ({})),
      getCurrentRole: 'agent',
    },
  },
}));

import { useCallsStore } from 'dashboard/stores/calls';
import { isOutboundInitiationActive } from 'customDashboard/composables/wavoip/useWavoipActiveCall';
import {
  handleVoiceCallCreated,
  handleVoiceCallUpdated,
  isStaleWavoipRingingMessage,
  markCallDismissed,
  isCallDismissed,
} from '../voice';
import { CALL_SID_SET_CAP } from 'customDashboard/lib/voice/cappedSet';

const nowSeconds = () => Math.floor(Date.now() / 1000);

const buildMessage = overrides => ({
  content_type: 'voice_call',
  message_type: 0,
  conversation_id: 1,
  inbox_id: 2,
  created_at: nowSeconds(),
  sender: { id: 99 },
  call: {
    provider: VOICE_CALL_PROVIDERS.WAVOIP,
    provider_call_id: 'call_001',
    status: 'ringing',
    direction: 'incoming',
  },
  ...overrides,
});

describe('isStaleWavoipRingingMessage', () => {
  it('returns false for a fresh ringing wavoip message', () => {
    expect(isStaleWavoipRingingMessage(buildMessage())).toBe(false);
  });

  it('returns true for a wavoip ringing message older than the stale window', () => {
    const message = buildMessage({
      created_at: nowSeconds() - 10 * 60,
    });
    expect(isStaleWavoipRingingMessage(message)).toBe(true);
  });

  it('returns false for non-ringing statuses regardless of age', () => {
    const message = buildMessage({
      created_at: nowSeconds() - 10 * 60,
      call: {
        provider: VOICE_CALL_PROVIDERS.WAVOIP,
        status: 'completed',
      },
    });
    expect(isStaleWavoipRingingMessage(message)).toBe(false);
  });

  it('returns false for non-wavoip providers', () => {
    const message = buildMessage({
      created_at: nowSeconds() - 10 * 60,
      call: { provider: VOICE_CALL_PROVIDERS.WHATSAPP, status: 'ringing' },
    });
    expect(isStaleWavoipRingingMessage(message)).toBe(false);
  });
});

describe('handleVoiceCallCreated / handleVoiceCallUpdated ghost-call guard', () => {
  beforeEach(() => {
    setActivePinia(createPinia());
    isOutboundInitiationActive.mockReturnValue(false);
  });

  it('ignores a stale ringing wavoip voice_call message', () => {
    const message = buildMessage({ created_at: nowSeconds() - 10 * 60 });

    handleVoiceCallCreated(message, 99, 'online');

    expect(useCallsStore().calls).toHaveLength(0);
  });

  it('adds a fresh ringing wavoip voice_call message', () => {
    const message = buildMessage();

    handleVoiceCallCreated(message, 1, 'online');

    expect(useCallsStore().calls).toHaveLength(1);
  });

  it('does not re-add a stale ringing call on update', () => {
    const commit = vi.fn();
    const message = buildMessage({
      created_at: nowSeconds() - 10 * 60,
      sender: null,
      call: {
        provider: VOICE_CALL_PROVIDERS.WAVOIP,
        provider_call_id: 'call_002',
        status: 'ringing',
        direction: 'incoming',
      },
    });

    handleVoiceCallUpdated(commit, message, 1, 'online');

    expect(useCallsStore().calls).toHaveLength(0);
  });
});

describe('markCallDismissed cap', () => {
  it('evicts the oldest sid once the set exceeds the cap', () => {
    const first = `cap_first_${Date.now()}`;
    markCallDismissed(first);
    for (let i = 0; i < CALL_SID_SET_CAP; i += 1) {
      markCallDismissed(`cap_${first}_${i}`);
    }

    expect(isCallDismissed(first)).toBe(false);
    expect(isCallDismissed(`cap_${first}_${CALL_SID_SET_CAP - 1}`)).toBe(true);
  });
});
