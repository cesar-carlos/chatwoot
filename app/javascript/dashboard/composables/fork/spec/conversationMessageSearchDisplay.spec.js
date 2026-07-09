import { describe, expect, it } from 'vitest';
import { buildSearchResultDisplayMessage } from '../conversationMessageSearchDisplay';

describe('buildSearchResultDisplayMessage', () => {
  it('uses email subject when the query matches subject but not body', () => {
    const message = {
      id: 1,
      content: 'Please see attached',
      matched_on: 'content',
      content_attributes: { email: { subject: 'Invoice for March' } },
    };

    const display = buildSearchResultDisplayMessage({
      message,
      searchQuery: 'invoice',
    });

    expect(display.content).toBe('Invoice for March');
  });

  it('keeps body content when the query matches the body', () => {
    const message = {
      id: 2,
      content: 'Invoice details inside',
      content_attributes: { email: { subject: 'Hello' } },
    };

    const display = buildSearchResultDisplayMessage({
      message,
      searchQuery: 'invoice',
    });

    expect(display.content).toBe('Invoice details inside');
  });

  it('uses transcription text for transcription-only matches', () => {
    const message = {
      id: 3,
      content: '',
      matched_on: 'transcription',
    };

    const display = buildSearchResultDisplayMessage({
      message,
      searchQuery: 'voicemail',
      transcriptText: 'Please check the voicemail',
    });

    expect(display.content).toBe('Please check the voicemail');
  });
});
