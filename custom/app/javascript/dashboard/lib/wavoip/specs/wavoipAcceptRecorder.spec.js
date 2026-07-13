import { beforeEach, describe, expect, it, vi } from 'vitest';
import { createPinia, setActivePinia } from 'pinia';
import { useCallsStore } from 'dashboard/stores/calls';
import CallsAPI from 'customDashboard/api/calls';
import {
  clearAcceptedByQueue,
  flushAcceptedByRecording,
  queueAcceptedByRecording,
} from '../wavoipAcceptRecorder';

vi.mock('@wavoip/wavoip-api', () => ({ Wavoip: vi.fn() }));
vi.mock('customDashboard/lib/wavoip/wavoipSdkPort', () => ({
  loadWavoipSdk: vi.fn(),
}));

vi.mock('customDashboard/api/calls', () => ({
  default: {
    recordAccept: vi.fn(),
    joinCall: vi.fn(),
  },
}));

describe('wavoipAcceptRecorder', () => {
  beforeEach(() => {
    vi.useFakeTimers();
    clearAcceptedByQueue();
    CallsAPI.recordAccept.mockReset();
    CallsAPI.joinCall.mockReset();
    CallsAPI.joinCall.mockResolvedValue(undefined);
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
    const flushPromise = flushAcceptedByRecording('call-1', {
      onFailure: vi.fn(),
    });

    await vi.advanceTimersByTimeAsync(1000);
    await vi.advanceTimersByTimeAsync(2000);
    await flushPromise;

    expect(CallsAPI.joinCall).toHaveBeenCalledWith(42);
    expect(CallsAPI.recordAccept).toHaveBeenCalledTimes(3);
    expect(CallsAPI.recordAccept).toHaveBeenCalledWith(42);
  });

  it('resolves db call id via wavoipOfferId when callSid differs', async () => {
    CallsAPI.recordAccept.mockResolvedValue(undefined);

    const store = useCallsStore();
    store.addCall({
      callSid: 'sdk-offer-1',
      wavoipOfferId: 'cable-call-1',
      callId: 99,
    });

    queueAcceptedByRecording('cable-call-1');
    await flushAcceptedByRecording('cable-call-1');

    expect(CallsAPI.joinCall).toHaveBeenCalledWith(99);
    expect(CallsAPI.recordAccept).toHaveBeenCalledWith(99);
  });
});
