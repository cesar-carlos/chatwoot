import { describe, expect, it } from 'vitest';
import { VOICE_CALL_PROVIDERS } from 'dashboard/helper/inbox';
import { VOICE_CALL_STATUS } from 'dashboard/components-next/message/constants';
import {
  inferAudioExtension,
  resolveVoiceCallRecordingUrl,
  shouldShowRecordingProcessing,
  shouldShowVoiceCallRecording,
} from '../voiceCallRecording';

describe('shouldShowVoiceCallRecording', () => {
  const base = {
    provider: VOICE_CALL_PROVIDERS.WAVOIP,
    callStatus: VOICE_CALL_STATUS.COMPLETED,
    recordingUrl: 'https://storage.wavoip.com/sample.ogg',
    callRecordingEnabled: true,
  };

  it('shows recording for completed wavoip calls when enabled', () => {
    expect(shouldShowVoiceCallRecording(base)).toBe(true);
  });

  it('hides recording when inbox recording is disabled', () => {
    expect(
      shouldShowVoiceCallRecording({ ...base, callRecordingEnabled: false })
    ).toBe(false);
  });

  it('hides recording while call is ringing', () => {
    expect(
      shouldShowVoiceCallRecording({
        ...base,
        callStatus: VOICE_CALL_STATUS.RINGING,
      })
    ).toBe(false);
  });

  it('hides recording when URL is missing', () => {
    expect(shouldShowVoiceCallRecording({ ...base, recordingUrl: null })).toBe(
      false
    );
  });

  it('does not gate non-wavoip providers', () => {
    expect(
      shouldShowVoiceCallRecording({
        ...base,
        provider: VOICE_CALL_PROVIDERS.WHATSAPP,
        callStatus: VOICE_CALL_STATUS.RINGING,
        callRecordingEnabled: false,
      })
    ).toBe(true);
  });

  it('shows wavoip recording when call_recording_enabled is undefined (default on)', () => {
    expect(
      shouldShowVoiceCallRecording({
        ...base,
        callRecordingEnabled: undefined,
      })
    ).toBe(true);
  });
});

describe('shouldShowRecordingProcessing', () => {
  const base = {
    provider: VOICE_CALL_PROVIDERS.WAVOIP,
    callStatus: VOICE_CALL_STATUS.COMPLETED,
    recordingUrl: null,
    callRecordingEnabled: true,
    completedAtMs: Date.now() - 60_000,
  };

  it('shows processing state for recent completed calls without URL', () => {
    expect(shouldShowRecordingProcessing(base)).toBe(true);
  });

  it('hides processing when recording URL exists', () => {
    expect(
      shouldShowRecordingProcessing({
        ...base,
        recordingUrl: 'https://storage.wavoip.com/foo.ogg',
      })
    ).toBe(false);
  });

  it('hides processing when recording is disabled on inbox', () => {
    expect(
      shouldShowRecordingProcessing({ ...base, callRecordingEnabled: false })
    ).toBe(false);
  });
});

describe('resolveVoiceCallRecordingUrl', () => {
  it('prefers active storage attachment', () => {
    const attachment = {
      dataUrl: '/rails/active_storage/blobs/1',
      fileType: 'audio',
    };

    expect(
      resolveVoiceCallRecordingUrl({
        audioAttachment: attachment,
        call: {},
        contentAttributes: {},
      })
    ).toBe(attachment);
  });

  it('falls back to call recording URL', () => {
    const result = resolveVoiceCallRecordingUrl({
      audioAttachment: null,
      call: { recordingUrl: 'https://storage.wavoip.com/foo.ogg' },
      contentAttributes: {},
    });

    expect(result?.dataUrl).toBe('https://storage.wavoip.com/foo.ogg');
    expect(result?.extension).toBe('ogg');
  });

  it('infers extension from recording URL', () => {
    const wavResult = resolveVoiceCallRecordingUrl({
      audioAttachment: null,
      call: { recordingUrl: 'https://storage.wavoip.com/foo.wav' },
      contentAttributes: {},
    });

    expect(wavResult?.extension).toBe('wav');
  });
});

describe('inferAudioExtension', () => {
  it('defaults to ogg when extension is missing', () => {
    expect(inferAudioExtension('https://storage.wavoip.com/foo')).toBe('ogg');
  });

  it('parses extension before query string', () => {
    expect(
      inferAudioExtension('https://storage.wavoip.com/foo.mp3?token=1')
    ).toBe('mp3');
  });
});
