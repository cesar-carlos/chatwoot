import { isWavoipDeviceAtChannelCapacity } from 'customDashboard/lib/wavoip/wavoipDeviceStatus';

/**
 * Cheap, synchronous checks that predict an outbound Wavoip call will fail
 * before we ever touch the SDK. Channel capacity is still a hard client gate.
 * `Device.restricted` is informational only (SDK 2.6.2+): the backend still
 * allows calls to known contacts, so we do not block here.
 */
export function wavoipOutboundBlockedReasonKey(inboxId) {
  if (isWavoipDeviceAtChannelCapacity(inboxId)) {
    return 'CONVERSATION.WAVOIP_CALL.CHANNELS_FULL';
  }
  return null;
}
