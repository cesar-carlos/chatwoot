import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

vi.mock('dashboard/composables', () => ({
  useAlert: vi.fn(),
}));

vi.mock('customDashboard/lib/wavoip/wavoipClientRegistry', () => ({
  getWavoipClientEntry: vi.fn(() => null),
}));

import { STATS_POLL_MS, wireCallDiagnostics } from '../wavoipCallDiagnostics';
import {
  clearWavoipDiagnostics,
  exportWavoipDiagnostics,
} from '../wavoipDiagnosticsCollector';

describe('wireCallDiagnostics', () => {
  let hidden = false;

  beforeEach(() => {
    hidden = false;
    vi.useFakeTimers();
    clearWavoipDiagnostics();
    Object.defineProperty(document, 'hidden', {
      configurable: true,
      get: () => hidden,
    });
  });

  afterEach(() => {
    vi.useRealTimers();
    vi.restoreAllMocks();
  });

  const createCall = getStats => ({
    on: vi.fn(),
    off: vi.fn(),
    getStats,
  });

  it('polls getStats on the diagnostics interval', async () => {
    const getStats = vi.fn().mockResolvedValue({ rtt: 12 });
    const unwire = wireCallDiagnostics(createCall(getStats), {
      inboxId: 1,
      callId: 'call-1',
    });

    await vi.advanceTimersByTimeAsync(STATS_POLL_MS);

    expect(getStats).toHaveBeenCalledTimes(1);
    unwire();
  });

  it('skips the stats poll while the document is hidden', async () => {
    hidden = true;
    const getStats = vi.fn().mockResolvedValue({ rtt: 12 });
    const unwire = wireCallDiagnostics(createCall(getStats), {
      inboxId: 1,
      callId: 'call-1',
    });

    await vi.advanceTimersByTimeAsync(STATS_POLL_MS);

    expect(getStats).not.toHaveBeenCalled();
    unwire();
  });

  it('takes an extra getStats snapshot when exporting diagnostics', async () => {
    const getStats = vi.fn().mockResolvedValue({ rtt: 9 });
    const unwire = wireCallDiagnostics(createCall(getStats), {
      inboxId: 1,
      callId: 'call-1',
    });

    const payload = JSON.parse(
      await exportWavoipDiagnostics({ inboxId: 1, callId: 'call-1' })
    );

    expect(getStats).toHaveBeenCalledTimes(1);
    expect(payload.recentStats.at(-1).stats).toEqual({ rtt: 9 });
    unwire();
  });
});
