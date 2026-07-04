import { describe, expect, it } from 'vitest';
import { VOICE_CALL_PROVIDERS } from 'dashboard/helper/inbox';
import { VOICE_CALL_STATUS } from 'dashboard/components-next/message/constants';
import {
  resolveVoiceCallRecordingUrl,
  shouldShowVoiceCallRecording,
} from 'customDashboard/lib/wavoip/voiceCallRecording';

// Smoke: VoiceCall.vue gates AudioChip via these helpers — keep in sync.
describe('VoiceCall recording gate (smoke)', () => {
  const recordingUrl = 'https://storage.wavoip.com/sample.ogg';

  it('hides wavoip player when inbox recording is disabled', () => {
    expect(
      shouldShowVoiceCallRecording({
        provider: VOICE_CALL_PROVIDERS.WAVOIP,
        callStatus: VOICE_CALL_STATUS.COMPLETED,
        recordingUrl,
        callRecordingEnabled: false,
      })
    ).toBe(false);
  });

  it('shows wavoip player for completed calls with URL and recording enabled', () => {
    const attachment = resolveVoiceCallRecordingUrl({
      audioAttachment: null,
      call: { recordingUrl, provider: VOICE_CALL_PROVIDERS.WAVOIP },
      contentAttributes: {},
    });

    expect(
      shouldShowVoiceCallRecording({
        provider: VOICE_CALL_PROVIDERS.WAVOIP,
        callStatus: VOICE_CALL_STATUS.COMPLETED,
        recordingUrl: attachment?.dataUrl,
        callRecordingEnabled: true,
      })
    ).toBe(true);
  });
});
