import { beforeEach, describe, expect, it, vi } from 'vitest';
import { createPinia, setActivePinia } from 'pinia';
import { useCallsStore } from 'dashboard/stores/calls';
import CallsAPI from 'customDashboard/api/calls';
import {
  clearAcceptedByQueue,
  flushAcceptedByRecording,
  queueAcceptedByRecording,
} from '../wavoipAcceptRecorder';

vi.mock('customDashboard/api/calls', () => ({
  default: {
    recordAccept: vi.fn(),
  },
}));

describe('wavoipAcceptRecorder', () => {
  beforeEach(() => {
    vi.useFakeTimers();
    clearAcceptedByQueue();
    CallsAPI.recordAccept.mockReset();
    setActivePinia(createPinia());
  });

  it('retries recordAccept with backoff and succeeds on third attempt', async () => {
    CallsAPI.recordAccept
      .mockRejectedValueOnce(new Error('network'))
      .mockRejectedValueOnce(new Error('network'))
      .mockResolvedValueOnce(undefined);

    const store = useCallsStore();
    store.addCall({ callSid: 'call-1', callId: 42 });

    queueAcceptedByRecording('call-1');
    const flushPromise = flushAcceptedByRecording('call-1');

    await vi.advanceTimersByTimeAsync(1000);
    await vi.advanceTimersByTimeAsync(2000);
    await flushPromise;

    expect(CallsAPI.recordAccept).toHaveBeenCalledTimes(3);
    expect(CallsAPI.recordAccept).toHaveBeenCalledWith(42);
  });
});
