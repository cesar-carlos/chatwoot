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

  it('retries join with backoff and succeeds on third attempt', async () => {
    CallsAPI.joinCall
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

    expect(CallsAPI.joinCall).toHaveBeenCalledTimes(3);
    expect(CallsAPI.joinCall).toHaveBeenCalledWith(42);
    expect(CallsAPI.recordAccept).not.toHaveBeenCalled();
  });

  it('resolves db call id via wavoipOfferId when callSid differs', async () => {
    const store = useCallsStore();
    store.addCall({
      callSid: 'sdk-offer-1',
      wavoipOfferId: 'cable-call-1',
      callId: 99,
    });

    queueAcceptedByRecording('cable-call-1');
    await flushAcceptedByRecording('cable-call-1');

    expect(CallsAPI.joinCall).toHaveBeenCalledWith(99);
    expect(CallsAPI.recordAccept).not.toHaveBeenCalled();
  });

  it('does not retry on 409 conflict and invokes onConflict', async () => {
    const conflict = Object.assign(new Error('conflict'), {
      response: { status: 409 },
    });
    CallsAPI.joinCall.mockRejectedValue(conflict);

    const onConflict = vi.fn();
    const onFailure = vi.fn();
    const store = useCallsStore();
    store.addCall({ callSid: 'call-conflict', callId: 7 });

    queueAcceptedByRecording('call-conflict');
    await flushAcceptedByRecording('call-conflict', { onConflict, onFailure });

    expect(CallsAPI.joinCall).toHaveBeenCalledTimes(1);
    expect(CallsAPI.recordAccept).not.toHaveBeenCalled();
    expect(onConflict).toHaveBeenCalled();
    expect(onFailure).not.toHaveBeenCalled();
  });

  it('flush only joins and does not PATCH accept', async () => {
    CallsAPI.joinCall.mockResolvedValue(undefined);

    const store = useCallsStore();
    store.addCall({ callSid: 'call-join-only', callId: 11 });

    queueAcceptedByRecording('call-join-only');
    await flushAcceptedByRecording('call-join-only');

    expect(CallsAPI.joinCall).toHaveBeenCalledWith(11);
    expect(CallsAPI.recordAccept).not.toHaveBeenCalled();
  });
});
