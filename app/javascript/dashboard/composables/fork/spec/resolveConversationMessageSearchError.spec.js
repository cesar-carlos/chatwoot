import { describe, expect, it, vi } from 'vitest';
import { resolveConversationMessageSearchError } from '../resolveConversationMessageSearchError';

const t = key => key;

describe('resolveConversationMessageSearchError', () => {
  it('returns rate limit message for 429', () => {
    const message = resolveConversationMessageSearchError(
      { response: { status: 429 } },
      t
    );

    expect(message).toBe('CONVERSATION.MESSAGE_SEARCH.ERROR_RATE_LIMIT');
  });

  it('maps validation errors to i18n keys', () => {
    const message = resolveConversationMessageSearchError(
      {
        response: {
          status: 422,
          data: { error: 'Search query must be between 2 and 200 characters' },
        },
      },
      t
    );

    expect(message).toBe('CONVERSATION.MESSAGE_SEARCH.ERROR_QUERY_LENGTH');
  });

  it('returns search-specific not found message for 404', () => {
    const message = resolveConversationMessageSearchError(
      { response: { status: 404 } },
      t
    );

    expect(message).toBe('CONVERSATION.MESSAGE_SEARCH.ERROR_NOT_FOUND');
  });

  it('returns server error text when present', () => {
    const message = resolveConversationMessageSearchError(
      {
        response: {
          status: 500,
          data: { error: 'Database unavailable' },
        },
      },
      t
    );

    expect(message).toBe('Database unavailable');
  });

  it('falls back to generic error', () => {
    const message = resolveConversationMessageSearchError(new Error('network'), t);

    expect(message).toBe('CONVERSATION.MESSAGE_SEARCH.ERROR');
  });
});
