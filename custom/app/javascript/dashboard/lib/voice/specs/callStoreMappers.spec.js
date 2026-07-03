import { describe, expect, it } from 'vitest';
import { VOICE_CALL_PROVIDERS } from 'dashboard/helper/inbox';
import { VOICE_CALL_DIRECTION } from 'dashboard/components-next/message/constants';
import {
  mapCableToStoreEntry,
  mapWavoipOfferToStoreEntry,
  mergeStoreEntries,
  reconcileWavoipStoreEntry,
  findWavoipCallForOffer,
} from '../callStoreMappers';

describe('callStoreMappers', () => {
  describe('mapCableToStoreEntry', () => {
    it('maps ActionCable voice_call.incoming payload', () => {
      const entry = mapCableToStoreEntry({
        call_id: 'wavoip_cable_001',
        id: 42,
        provider: 'wavoip',
        conversation_id: 7,
        inbox_id: 3,
        caller: { name: 'Alice', phone: '+15551234567' },
      });

      expect(entry).toEqual({
        callSid: 'wavoip_cable_001',
        callId: 42,
        provider: 'wavoip',
        conversationId: 7,
        inboxId: 3,
        callDirection: VOICE_CALL_DIRECTION.INBOUND,
        caller: { name: 'Alice', phone: '+15551234567' },
        wavoipOfferId: 'wavoip_cable_001',
      });
    });
  });

  describe('mapWavoipOfferToStoreEntry', () => {
    it('maps SDK offer before webhook persistence', () => {
      const entry = mapWavoipOfferToStoreEntry(
        {
          id: 'offer_001',
          peer: {
            phone: '+15559876543',
            displayName: 'Bob',
            profilePicture: 'https://example.com/avatar.png',
          },
        },
        { inboxId: 5, conversationId: null }
      );

      expect(entry).toMatchObject({
        callSid: 'offer_001',
        provider: VOICE_CALL_PROVIDERS.WAVOIP,
        wavoipOfferId: 'offer_001',
        callDirection: VOICE_CALL_DIRECTION.INBOUND,
        inboxId: 5,
        caller: {
          name: 'Bob',
          phone: '+15559876543',
          avatar: 'https://example.com/avatar.png',
        },
      });
    });
  });

  describe('reconcileWavoipStoreEntry', () => {
    it('merges webhook-after-SDK so DB ids and caller survive', () => {
      const sdkFirst = mapWavoipOfferToStoreEntry(
        {
          id: 'corr_001',
          peer: { phone: '+15550001111', displayName: 'Carol' },
        },
        { inboxId: 2 }
      );
      const cableLater = mapCableToStoreEntry({
        call_id: 'corr_001',
        id: 99,
        conversation_id: 12,
        inbox_id: 2,
      });

      const merged = reconcileWavoipStoreEntry(sdkFirst, cableLater);

      expect(merged).toMatchObject({
        callSid: 'corr_001',
        callId: 99,
        conversationId: 12,
        inboxId: 2,
        caller: sdkFirst.caller,
        wavoipOfferId: 'corr_001',
      });
    });

    it('merges SDK-after-webhook without dropping persisted ids', () => {
      const cableFirst = mapCableToStoreEntry({
        call_id: 'corr_002',
        id: 88,
        conversation_id: 15,
        inbox_id: 4,
        caller: { name: 'Dave', phone: '+15552223333' },
      });
      const sdkLater = mapWavoipOfferToStoreEntry(
        {
          id: 'corr_002',
          peer: { phone: '+15552223333', displayName: 'Dave' },
        },
        { inboxId: 4, conversationId: 15 }
      );

      const merged = reconcileWavoipStoreEntry(cableFirst, sdkLater);

      expect(merged.callId).toBe(88);
      expect(merged.conversationId).toBe(15);
      expect(merged.caller).toEqual(cableFirst.caller);
    });
  });

  describe('findWavoipCallForOffer', () => {
    it('matches awaiting cable row when SDK offer id differs from webhook call_id', () => {
      const calls = [
        {
          callSid: 'webhook_call_id',
          provider: VOICE_CALL_PROVIDERS.WAVOIP,
          awaitingSdkOffer: true,
          inboxId: 106,
          isActive: false,
        },
      ];

      const match = findWavoipCallForOffer(calls, { id: 'sdk_offer_id' }, 106);

      expect(match?.callSid).toBe('webhook_call_id');
    });
  });

  describe('mergeStoreEntries', () => {
    it('preserves caller when the incoming patch omits it', () => {
      const existing = {
        callSid: 'x',
        caller: { name: 'Eve', phone: '+15554445555' },
        callId: 1,
      };
      const incoming = { callSid: 'x', status: 'ringing' };

      expect(mergeStoreEntries(existing, incoming).caller).toEqual(
        existing.caller
      );
    });
  });
});
