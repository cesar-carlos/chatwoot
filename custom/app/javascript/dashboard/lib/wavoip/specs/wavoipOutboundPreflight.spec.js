import {
  setWavoipActiveCalls,
  setWavoipNumChannels,
  setWavoipRestricted,
  clearWavoipDeviceStatus,
} from 'customDashboard/lib/wavoip/wavoipDeviceStatus';
import { wavoipOutboundBlockedReasonKey } from '../wavoipOutboundPreflight';

describe('wavoipOutboundBlockedReasonKey', () => {
  const inboxId = 501;

  beforeEach(() => {
    clearWavoipDeviceStatus(inboxId);
  });

  it('returns null when the device is free and under capacity', () => {
    expect(wavoipOutboundBlockedReasonKey(inboxId)).toBeNull();
  });

  it('does not block a Meta-restricted device (backend decides)', () => {
    setWavoipRestricted(inboxId, true);
    setWavoipNumChannels(inboxId, 2);
    setWavoipActiveCalls(inboxId, 1);

    expect(wavoipOutboundBlockedReasonKey(inboxId)).toBeNull();
  });

  it('flags a device at channel capacity', () => {
    setWavoipNumChannels(inboxId, 2);
    setWavoipActiveCalls(inboxId, 2);

    expect(wavoipOutboundBlockedReasonKey(inboxId)).toBe(
      'CONVERSATION.WAVOIP_CALL.CHANNELS_FULL'
    );
  });

  it('allows the call when channels are configured but under capacity', () => {
    setWavoipNumChannels(inboxId, 2);
    setWavoipActiveCalls(inboxId, 1);

    expect(wavoipOutboundBlockedReasonKey(inboxId)).toBeNull();
  });
});
