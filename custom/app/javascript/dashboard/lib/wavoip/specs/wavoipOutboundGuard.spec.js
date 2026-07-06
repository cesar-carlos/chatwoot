import { beforeEach, describe, expect, it, vi } from 'vitest';
import { VOICE_CALL_DIRECTION } from 'dashboard/components-next/message/constants';

const {
  isWavoipSdkCallOwned,
  getRingingProviderCallId,
  isOutboundInitiationActive,
} = vi.hoisted(() => ({
  isWavoipSdkCallOwned: vi.fn(() => false),
  getRingingProviderCallId: vi.fn(() => null),
  isOutboundInitiationActive: vi.fn(() => false),
}));

vi.mock('customDashboard/composables/wavoip/useWavoipActiveCall', () => ({
  isWavoipSdkCallOwned,
  getRingingProviderCallId,
  isOutboundInitiationActive,
}));

import {
  isAgentInitiatedWavoipCallId,
  isAgentInitiatedWavoipStoreCall,
  shouldIgnoreInboundWavoipCable,
  shouldIgnoreInboundWavoipOffer,
} from '../wavoipOutboundGuard';

describe('wavoipOutboundGuard', () => {
  beforeEach(() => {
    isWavoipSdkCallOwned.mockReset().mockReturnValue(false);
    getRingingProviderCallId.mockReset().mockReturnValue(null);
  });

  describe('isAgentInitiatedWavoipCallId', () => {
    it('returns true when SDK owns the call', () => {
      isWavoipSdkCallOwned.mockReturnValue(true);
      expect(isAgentInitiatedWavoipCallId('out_001')).toBe(true);
    });

    it('returns true when call is ringing outbound', () => {
      getRingingProviderCallId.mockReturnValue('out_ring');
      expect(isAgentInitiatedWavoipCallId('out_ring')).toBe(true);
    });
  });

  describe('isAgentInitiatedWavoipStoreCall', () => {
    it('returns true for outbound store entries', () => {
      expect(
        isAgentInitiatedWavoipStoreCall({
          provider: 'wavoip',
          callDirection: VOICE_CALL_DIRECTION.OUTBOUND,
          callSid: 'out_001',
        })
      ).toBe(true);
    });
  });

  describe('shouldIgnoreInboundWavoipOffer', () => {
    it('ignores offer when agent started outbound call', () => {
      isWavoipSdkCallOwned.mockImplementation(id => id === 'sdk_out');
      expect(
        shouldIgnoreInboundWavoipOffer(
          { id: 'sdk_out' },
          { calls: [], inboxId: 1 }
        )
      ).toBe(true);
    });

    it('ignores offer when store already has outbound row', () => {
      expect(
        shouldIgnoreInboundWavoipOffer(
          { id: 'sdk_out' },
          {
            inboxId: 1,
            calls: [
              {
                provider: 'wavoip',
                callSid: 'sdk_out',
                callDirection: VOICE_CALL_DIRECTION.OUTBOUND,
              },
            ],
          }
        )
      ).toBe(true);
    });

    it('ignores offer during outbound initiation', () => {
      isOutboundInitiationActive.mockReturnValue(true);
      expect(
        shouldIgnoreInboundWavoipOffer(
          { id: 'race_offer' },
          { inboxId: 106, calls: [] }
        )
      ).toBe(true);
    });

    it('accepts true inbound offers', () => {
      expect(
        shouldIgnoreInboundWavoipOffer(
          { id: 'in_001' },
          { inboxId: 1, calls: [] }
        )
      ).toBe(false);
    });
  });

  describe('shouldIgnoreInboundWavoipCable', () => {
    it('ignores cable when payload marks outbound direction', () => {
      expect(
        shouldIgnoreInboundWavoipCable(
          { call_id: 'server_out', call_direction: 'outbound' },
          { calls: [] }
        )
      ).toBe(true);
    });

    it('ignores cable when SDK owns outbound session', () => {
      getRingingProviderCallId.mockReturnValue('cable_out');
      expect(
        shouldIgnoreInboundWavoipCable({ call_id: 'cable_out' }, { calls: [] })
      ).toBe(true);
    });

    it('ignores cable when matching store row is outbound', () => {
      expect(
        shouldIgnoreInboundWavoipCable(
          { call_id: 'webhook_out', id: 10 },
          {
            calls: [
              {
                provider: 'wavoip',
                callSid: 'webhook_out',
                callDirection: VOICE_CALL_DIRECTION.OUTBOUND,
              },
            ],
          }
        )
      ).toBe(true);
    });
  });
});
