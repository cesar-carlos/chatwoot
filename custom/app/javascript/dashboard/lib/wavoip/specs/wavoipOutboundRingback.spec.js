import { describe, expect, it, vi, beforeEach, afterEach } from 'vitest';
import { VOICE_CALL_DIRECTION } from 'dashboard/components-next/message/constants';
import { VOICE_CALL_PROVIDERS } from 'dashboard/helper/inbox';
import {
  INBOUND_RINGTONE_VOLUME,
  WAVOIP_OUTBOUND_RINGBACK_VOLUME,
  isWavoipOutboundRingbackPlaying,
  resetWavoipOutboundRingback,
  ringtoneVolumeForPlayback,
  shouldPlayWavoipOutboundRingback,
  startWavoipOutboundRingback,
  stopWavoipOutboundRingback,
  unlockWavoipOutboundRingback,
} from '../wavoipOutboundRingback';

const wavoipOutbound = (overrides = {}) => ({
  provider: VOICE_CALL_PROVIDERS.WAVOIP,
  callDirection: VOICE_CALL_DIRECTION.OUTBOUND,
  callSid: 'out-1',
  isActive: false,
  ...overrides,
});

describe('shouldPlayWavoipOutboundRingback', () => {
  it('returns true for ringing Wavoip outbound', () => {
    expect(shouldPlayWavoipOutboundRingback(wavoipOutbound())).toBe(true);
  });

  it('returns false for inbound Wavoip', () => {
    expect(
      shouldPlayWavoipOutboundRingback(
        wavoipOutbound({ callDirection: VOICE_CALL_DIRECTION.INBOUND })
      )
    ).toBe(false);
  });

  it('returns false for Meta outbound', () => {
    expect(
      shouldPlayWavoipOutboundRingback(
        wavoipOutbound({ provider: VOICE_CALL_PROVIDERS.WHATSAPP })
      )
    ).toBe(false);
  });

  it('returns false when call is already active', () => {
    expect(
      shouldPlayWavoipOutboundRingback(wavoipOutbound({ isActive: true }))
    ).toBe(false);
  });

  it('returns false when callSid is silenced', () => {
    expect(
      shouldPlayWavoipOutboundRingback(wavoipOutbound(), {
        isSilenced: sid => sid === 'out-1',
      })
    ).toBe(false);
  });

  it('returns false when wavoipOfferId is silenced', () => {
    expect(
      shouldPlayWavoipOutboundRingback(
        wavoipOutbound({ wavoipOfferId: 'offer-9' }),
        { isSilenced: sid => sid === 'offer-9' }
      )
    ).toBe(false);
  });

  it('returns false for null call', () => {
    expect(shouldPlayWavoipOutboundRingback(null)).toBe(false);
  });
});

describe('ringtoneVolumeForPlayback', () => {
  it('uses full volume when inbound is ringing', () => {
    expect(
      ringtoneVolumeForPlayback({
        ringingInbound: true,
        ringingWavoipOutbound: true,
      })
    ).toBe(INBOUND_RINGTONE_VOLUME);
  });

  it('uses soft volume for outbound-only Wavoip ringback', () => {
    expect(
      ringtoneVolumeForPlayback({
        ringingInbound: false,
        ringingWavoipOutbound: true,
      })
    ).toBe(WAVOIP_OUTBOUND_RINGBACK_VOLUME);
  });

  it('defaults to full volume when nothing is ringing', () => {
    expect(
      ringtoneVolumeForPlayback({
        ringingInbound: false,
        ringingWavoipOutbound: false,
      })
    ).toBe(INBOUND_RINGTONE_VOLUME);
  });
});

describe('outbound ringback audio controls', () => {
  let ringbackElement;

  beforeEach(() => {
    resetWavoipOutboundRingback();
    vi.stubGlobal(
      'Audio',
      vi.fn(() => {
        ringbackElement = {
          loop: false,
          preload: '',
          volume: 1,
          muted: false,
          paused: true,
          currentTime: 0,
          play: vi.fn(() => {
            ringbackElement.paused = false;
            return Promise.resolve();
          }),
          pause: vi.fn(() => {
            ringbackElement.paused = true;
          }),
        };
        return ringbackElement;
      })
    );
  });

  afterEach(() => {
    resetWavoipOutboundRingback();
    vi.unstubAllGlobals();
  });

  it('unlocks with muted zero-volume play (no pause)', async () => {
    unlockWavoipOutboundRingback();
    await Promise.resolve();
    expect(ringbackElement.play).toHaveBeenCalled();
    expect(ringbackElement.pause).not.toHaveBeenCalled();
    expect(ringbackElement.muted).toBe(true);
    expect(ringbackElement.volume).toBe(0);
  });

  it('unmutes on start after unlock and stops cleanly', async () => {
    unlockWavoipOutboundRingback();
    startWavoipOutboundRingback();
    await Promise.resolve();
    expect(isWavoipOutboundRingbackPlaying()).toBe(true);
    expect(ringbackElement.muted).toBe(false);
    expect(ringbackElement.volume).toBe(WAVOIP_OUTBOUND_RINGBACK_VOLUME);

    stopWavoipOutboundRingback();
    expect(isWavoipOutboundRingbackPlaying()).toBe(false);
    expect(ringbackElement.pause).toHaveBeenCalled();
  });
});
