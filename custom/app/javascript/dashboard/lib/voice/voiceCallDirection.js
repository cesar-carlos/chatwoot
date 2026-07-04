import { VOICE_CALL_DIRECTION } from 'dashboard/components-next/message/constants';

// Wavoip's direction shows up under slightly different spellings depending on
// the source: the Rails enum ('outgoing'/'incoming'), the webhook/cable
// payload ('OUTBOUND'/'outbound'), and the SDK (implicitly inbound via
// `offer`). This is the single place that normalizes all of them to the two
// values the frontend actually branches on.
const OUTBOUND_VALUES = new Set([
  VOICE_CALL_DIRECTION.OUTBOUND,
  VOICE_CALL_DIRECTION.OUTGOING,
  'OUTBOUND',
  'OUTGOING',
]);

export const normalizeCallDirection = raw =>
  OUTBOUND_VALUES.has(raw)
    ? VOICE_CALL_DIRECTION.OUTBOUND
    : VOICE_CALL_DIRECTION.INBOUND;

export const isOutboundCallDirection = raw =>
  normalizeCallDirection(raw) === VOICE_CALL_DIRECTION.OUTBOUND;
