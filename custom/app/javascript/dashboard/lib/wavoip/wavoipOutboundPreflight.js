import {
  getWavoipDeviceStatus,
  isWavoipDeviceAtChannelCapacity,
} from 'customDashboard/lib/wavoip/wavoipDeviceStatus';

/**
 * Cheap, synchronous checks that predict an outbound Wavoip call will fail
 * before we ever touch the SDK. Without these, both the contact panel call
 * button and the missed-call "call back" bubble would attempt the call, let
 * it fail deep inside the SDK, and surface a generic "could not start the
 * call" message with no indication of *why* (device Meta-restricted, or all
 * channels busy).
 */
export function wavoipOutboundBlockedReasonKey(inboxId) {
  if (getWavoipDeviceStatus(inboxId).isRestricted.value) {
    return 'INBOX_MGMT.WAVOIP_CALL.DEVICE_STATUS.RESTRICTED';
  }
  if (isWavoipDeviceAtChannelCapacity(inboxId)) {
    return 'CONVERSATION.WAVOIP_CALL.CHANNELS_FULL';
  }
  return null;
}
