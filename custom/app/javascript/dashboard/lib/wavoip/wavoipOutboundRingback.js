import { VOICE_CALL_DIRECTION } from 'dashboard/components-next/message/constants';
import { VOICE_CALL_PROVIDERS } from 'dashboard/helper/inbox';

/** Soft ringback while Wavoip outbound is still unanswered (vs full inbound ring). */
export const WAVOIP_OUTBOUND_RINGBACK_VOLUME = 0.55;
export const INBOUND_RINGTONE_VOLUME = 1;

/** Outbound “chamando…” tone — not the inbound `ringtone.mp3`. */
export const RINGBACK_URL = '/audio/dashboard/ringback.mp3';

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
 * Call synchronously on the agent click (before any await) to satisfy
 * autoplay policy. Stays muted so nothing is heard until
 * startWavoipOutboundRingback() when the call widget appears.
 */
export function unlockWavoipOutboundRingback() {
  if (typeof window === 'undefined' || typeof Audio === 'undefined') return;
  if (ringbackPlaying) return;

  const audio = getRingbackAudio();
  audio.muted = true;
  audio.volume = 0;
  audio.play().catch(() => {});
}

/**
 * Unmute and play ringback — call after addCall / when the outbound widget
 * is visible (“Ligando…”), not on the raw click.
 */
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
