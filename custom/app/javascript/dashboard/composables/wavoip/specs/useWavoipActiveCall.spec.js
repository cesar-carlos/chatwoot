import { beforeEach, describe, expect, it, vi } from 'vitest';
import { createPinia, setActivePinia } from 'pinia';

vi.mock('customDashboard/lib/wavoip/wavoipCallDiagnostics', () => ({
  wireCallDiagnostics: vi.fn(() => vi.fn()),
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

import { useCallsStore } from 'dashboard/stores/calls';
import {
  clearActiveCall,
  clearRingingOutgoingCall,
  endActiveCall,
  getRingingProviderCallId,
  setActiveCall,
  setRingingOutgoingCall,
} from '../useWavoipActiveCall';
import { wireCallDiagnostics } from 'customDashboard/lib/wavoip/wavoipCallDiagnostics';

describe('useWavoipActiveCall', () => {
  beforeEach(() => {
    setActivePinia(createPinia());
    vi.clearAllMocks();
    clearActiveCall();
    clearRingingOutgoingCall();
  });

  it('clears activeInboxId when clearing a ringing outgoing call', () => {
    const firstCall = { id: 'ring_1' };
    const secondCall = { id: 'ring_2' };

    setRingingOutgoingCall(firstCall, {
      providerCallId: 'ring_1',
      inboxId: 5,
    });
    clearRingingOutgoingCall();

    setRingingOutgoingCall(secondCall, {
      providerCallId: 'ring_2',
      inboxId: 99,
    });

    expect(wireCallDiagnostics).toHaveBeenLastCalledWith(
      secondCall,
      expect.objectContaining({ inboxId: 99 })
    );
  });

  it('keeps the active call when SDK emits recoverable status DISCONNECTED', () => {
    const handlers = {};
    const sdkCall = {
      connectionStatus: 'connected',
      status: 'ACTIVE',
      on: vi.fn((event, handler) => {
        handlers[event] = handler;
      }),
      off: vi.fn(),
    };

    const store = useCallsStore();
    store.addCall({
      callSid: 'live_1',
      provider: 'wavoip',
      inboxId: 7,
      isActive: true,
    });

    setActiveCall(sdkCall, { providerCallId: 'live_1', inboxId: 7 });
    expect(handlers.status).toBeTypeOf('function');

    handlers.status('DISCONNECTED');

    expect(store.calls.some(c => c.callSid === 'live_1')).toBe(true);
  });

  it('restores the live call when SDK emits ACTIVE after DISCONNECTED', () => {
    const handlers = {};
    const sdkCall = {
      connectionStatus: 'connected',
      status: 'ACTIVE',
      on: vi.fn((event, handler) => {
        handlers[event] = handler;
      }),
      off: vi.fn(),
    };

    const store = useCallsStore();
    store.addCall({
      callSid: 'live_2',
      provider: 'wavoip',
      inboxId: 7,
      isActive: true,
    });

    setActiveCall(sdkCall, { providerCallId: 'live_2', inboxId: 7 });
    handlers.status('DISCONNECTED');
    handlers.status('ACTIVE');

    expect(store.calls.some(c => c.callSid === 'live_2')).toBe(true);
  });

  it('tears down the active call when local transport emits disconnected', () => {
    const handlers = {};
    const sdkCall = {
      connectionStatus: 'connected',
      on: vi.fn((event, handler) => {
        handlers[event] = handler;
      }),
      off: vi.fn(),
    };

    const store = useCallsStore();
    store.addCall({
      callSid: 'live_3',
      provider: 'wavoip',
      inboxId: 7,
      isActive: true,
    });

    setActiveCall(sdkCall, { providerCallId: 'live_3', inboxId: 7 });
    handlers.connectionStatus('disconnected');

    expect(store.calls.some(c => c.callSid === 'live_3')).toBe(false);
  });

  it('cancels a ringing outbound call and keeps it when the callee answers in the same instant', async () => {
    const ringing = {
      cancel: vi.fn().mockResolvedValue({ err: 'IS_NOT_OFFER' }),
      end: vi.fn(),
    };
    setRingingOutgoingCall(ringing, { providerCallId: 'ring_keep', inboxId: 4 });

    await endActiveCall('ring_keep');

    expect(ringing.cancel).toHaveBeenCalled();
    expect(ringing.end).not.toHaveBeenCalled();
    expect(getRingingProviderCallId()).toBe('ring_keep');
  });

  it('clears a ringing call after cancel is confirmed', async () => {
    const ringing = { cancel: vi.fn().mockResolvedValue({ err: null }) };
    setRingingOutgoingCall(ringing, { providerCallId: 'ring_ok', inboxId: 4 });

    await endActiveCall('ring_ok');

    expect(getRingingProviderCallId()).toBeNull();
  });

  it('ends an in-progress call with end()', async () => {
    const active = { end: vi.fn(), cancel: vi.fn(), on: vi.fn(), off: vi.fn() };
    setActiveCall(active, { providerCallId: 'live_end', inboxId: 1 });

    await endActiveCall('live_end');

    expect(active.end).toHaveBeenCalled();
    expect(active.cancel).not.toHaveBeenCalled();
  });
});
