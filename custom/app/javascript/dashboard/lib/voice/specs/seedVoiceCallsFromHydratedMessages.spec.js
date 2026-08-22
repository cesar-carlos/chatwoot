import { beforeEach, describe, expect, it, vi } from 'vitest';
import { INBOX_TYPES } from 'dashboard/helper/inbox';
import { CONTENT_TYPES } from 'dashboard/components-next/message/constants';

vi.mock('dashboard/helper/voice', () => ({
  handleVoiceCallCreated: vi.fn(),
}));

import { handleVoiceCallCreated } from 'dashboard/helper/voice';
import {
  resetSeedVoiceCallsFingerprints,
  seedVoiceCallsFromHydratedMessages,
} from '../seedVoiceCallsFromHydratedMessages';

const voiceInbox = {
  id: 2,
  channel_type: INBOX_TYPES.WAVOIP,
  voice_enabled: true,
};

const ringingMessage = {
  id: 10,
  content_type: CONTENT_TYPES.VOICE_CALL,
  conversation_id: 1,
  inbox_id: 2,
};

describe('seedVoiceCallsFromHydratedMessages', () => {
  beforeEach(() => {
    resetSeedVoiceCallsFingerprints();
    handleVoiceCallCreated.mockReset();
  });

  it('returns without scanning when no inbox has a voice provider', () => {
    seedVoiceCallsFromHydratedMessages({
      conversations: [{ id: 1, messages: [ringingMessage] }],
      inboxes: [{ id: 9, channel_type: INBOX_TYPES.WEB }],
      currentUserId: 1,
      currentUserAvailability: 'online',
    });

    expect(handleVoiceCallCreated).not.toHaveBeenCalled();
  });

  it('skips conversations that have no messages', () => {
    seedVoiceCallsFromHydratedMessages({
      conversations: [{ id: 1, messages: [] }, { id: 2 }],
      inboxes: [voiceInbox],
      currentUserId: 1,
      currentUserAvailability: 'online',
    });

    expect(handleVoiceCallCreated).not.toHaveBeenCalled();
  });

  it('seeds ringing messages and skips unchanged conversation fingerprints', () => {
    const conversations = [{ id: 1, messages: [ringingMessage] }];

    seedVoiceCallsFromHydratedMessages({
      conversations,
      inboxes: [voiceInbox],
      currentUserId: 7,
      currentUserAvailability: 'online',
    });
    seedVoiceCallsFromHydratedMessages({
      conversations,
      inboxes: [voiceInbox],
      currentUserId: 7,
      currentUserAvailability: 'online',
    });

    expect(handleVoiceCallCreated).toHaveBeenCalledTimes(1);
    expect(handleVoiceCallCreated).toHaveBeenCalledWith(
      ringingMessage,
      7,
      'online'
    );
  });

  it('reseeds after fingerprints are reset or the last message changes', () => {
    const conversations = [{ id: 1, messages: [ringingMessage] }];

    seedVoiceCallsFromHydratedMessages({
      conversations,
      inboxes: [voiceInbox],
      currentUserId: 1,
      currentUserAvailability: 'online',
    });

    resetSeedVoiceCallsFingerprints();
    seedVoiceCallsFromHydratedMessages({
      conversations,
      inboxes: [voiceInbox],
      currentUserId: 1,
      currentUserAvailability: 'online',
    });

    const nextMessage = { ...ringingMessage, id: 11 };
    seedVoiceCallsFromHydratedMessages({
      conversations: [{ id: 1, messages: [ringingMessage, nextMessage] }],
      inboxes: [voiceInbox],
      currentUserId: 1,
      currentUserAvailability: 'online',
    });

    expect(handleVoiceCallCreated).toHaveBeenCalledTimes(4);
  });

  it('still seeds WhatsApp voice inboxes, not only Wavoip', () => {
    seedVoiceCallsFromHydratedMessages({
      conversations: [{ id: 1, messages: [ringingMessage] }],
      inboxes: [
        {
          id: 3,
          channel_type: INBOX_TYPES.WHATSAPP,
          voice_enabled: true,
        },
      ],
      currentUserId: 1,
      currentUserAvailability: 'online',
    });

    expect(handleVoiceCallCreated).toHaveBeenCalledTimes(1);
  });
});
