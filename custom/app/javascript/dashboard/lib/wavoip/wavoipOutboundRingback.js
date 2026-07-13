import { VOICE_CALL_DIRECTION } from 'dashboard/components-next/message/constants';
import { VOICE_CALL_PROVIDERS } from 'dashboard/helper/inbox';

/** Soft ringback while Wavoip outbound is still unanswered (vs full inbound ring). */
export const WAVOIP_OUTBOUND_RINGBACK_VOLUME = 0.45;
export const INBOUND_RINGTONE_VOLUME = 1;

const RINGBACK_URL = '/audio/dashboard/ringtone.mp3';

let ringbackAudio = null;
let ringbackPlaying = false;

const getRingbackAudio = () => {
  if (!ringbackAudio) {
    ringbackAudio = new Audio(RINGBACK_URL);
    ringbackAudio.loop = true;
    ringbackAudio.preload = 'auto';
    ringbackAudio.volume = WAVOIP_OUTBOUND_RINGBACK_VOLUME;
  }
  return ringbackAudio;
};

/**
 * Call synchronously inside the agent click handler (before any await) so the
 * browser grants media playback. FloatingCallWidget is async-mounted and would
 * otherwise hit autoplay blocking after startCall resolves.
 *
 * Keeps a muted/zero-volume play running; startWavoipOutboundRingback() then
 * unmutes. Avoid pausing here — that races with start after awaits.
 */
export function unlockWavoipOutboundRingback() {
  if (typeof window === 'undefined' || typeof Audio === 'undefined') return;

  const audio = getRingbackAudio();
  if (ringbackPlaying) return;

  audio.muted = true;
  audio.volume = 0;
  audio.play().catch(() => {});
}

export function startWavoipOutboundRingback() {
  if (typeof window === 'undefined' || typeof Audio === 'undefined') return;

  const audio = getRingbackAudio();
  audio.muted = false;
  audio.volume = WAVOIP_OUTBOUND_RINGBACK_VOLUME;
  ringbackPlaying = true;
  if (audio.paused) {
    audio.play().catch(() => {
      ringbackPlaying = false;
    });
  }
}

export function stopWavoipOutboundRingback() {
  if (ringbackAudio) {
    ringbackAudio.pause();
    ringbackAudio.currentTime = 0;
    ringbackAudio.muted = false;
    ringbackAudio.volume = WAVOIP_OUTBOUND_RINGBACK_VOLUME;
  }
  ringbackPlaying = false;
}

/** Clears the singleton Audio (Vitest). */
export function resetWavoipOutboundRingback() {
  stopWavoipOutboundRingback();
  ringbackAudio = null;
}

export function isWavoipOutboundRingbackPlaying() {
  return ringbackPlaying;
}

/**
 * Whether this store call should play outbound ringback.
 * @param {object} call
 * @param {{ isSilenced?: (sid: string) => boolean }} [options]
 */
export function shouldPlayWavoipOutboundRingback(call, options = {}) {
  if (!call) return false;
  if (call.provider !== VOICE_CALL_PROVIDERS.WAVOIP) return false;
  if (call.callDirection !== VOICE_CALL_DIRECTION.OUTBOUND) return false;
  if (call.isActive) return false;

  const isSilenced = options.isSilenced || (() => false);
  if (call.callSid && isSilenced(call.callSid)) return false;
  if (call.wavoipOfferId && isSilenced(call.wavoipOfferId)) return false;

  return true;
}

/**
 * Volume for the shared inbound ringtone element when both may ring.
 * Inbound always wins (full volume).
 */
export function ringtoneVolumeForPlayback({
  ringingInbound,
  ringingWavoipOutbound,
}) {
  if (ringingInbound) return INBOUND_RINGTONE_VOLUME;
  if (ringingWavoipOutbound) return WAVOIP_OUTBOUND_RINGBACK_VOLUME;
  return INBOUND_RINGTONE_VOLUME;
}
