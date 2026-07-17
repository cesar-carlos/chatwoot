import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { effectScope } from 'vue';
import {
  useContactsRefreshLock,
  isContactsRefreshAlreadyRunningError,
} from '../useContactsRefreshLock';

describe('isContactsRefreshAlreadyRunningError', () => {
  it('detects already_running code', () => {
    expect(
      isContactsRefreshAlreadyRunningError({
        response: { data: { code: 'already_running' } },
      })
    ).toBe(true);
  });

  it('detects already running message fallback', () => {
    expect(
      isContactsRefreshAlreadyRunningError({
        response: {
          data: { error: 'Contact profile refresh already running' },
        },
      })
    ).toBe(true);
  });

  it('returns false for other errors', () => {
    expect(
      isContactsRefreshAlreadyRunningError({
        response: { data: { error: 'boom' } },
      })
    ).toBe(false);
    expect(isContactsRefreshAlreadyRunningError(null)).toBe(false);
  });
});

describe('useContactsRefreshLock', () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it('counts down remaining seconds', () => {
    const scope = effectScope();
    const api = scope.run(() => useContactsRefreshLock());

    api.startCountdown(2);
    expect(api.isLocked.value).toBe(true);
    expect(api.remainingSeconds.value).toBe(2);

    vi.advanceTimersByTime(1000);
    expect(api.remainingSeconds.value).toBe(1);

    vi.advanceTimersByTime(1000);
    expect(api.remainingSeconds.value).toBe(0);
    expect(api.isLocked.value).toBe(false);

    scope.stop();
  });
});
