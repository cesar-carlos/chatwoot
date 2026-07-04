import { beforeEach, describe, expect, it } from 'vitest';
import {
  setWavoipRestricted,
  setWavoipActiveCalls,
  setWavoipNumChannels,
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

  it('flags a Meta-restricted device before capacity', () => {
    setWavoipRestricted(inboxId, true);
    setWavoipNumChannels(inboxId, 1);
    setWavoipActiveCalls(inboxId, 1);

    expect(wavoipOutboundBlockedReasonKey(inboxId)).toBe(
      'INBOX_MGMT.WAVOIP_CALL.DEVICE_STATUS.RESTRICTED'
    );
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
