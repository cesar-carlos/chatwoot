import { describe, expect, it } from 'vitest';
import {
  formatQrDataUrl,
  isEvolutionPlaceholderPhone,
  normalizeEvolutionConnectionPayload,
} from '../evolutionConnectionPayload';

const qrcodeWebhookPayload = {
  qrcode: {
    instance: 'cw-test',
    code: '2@pairing-code-placeholder',
    base64: 'data:image/png;base64,iVBORw0KGgo=',
  },
};

describe('evolutionConnectionPayload', () => {
  describe('isEvolutionPlaceholderPhone', () => {
    it('detects placeholder numbers', () => {
      expect(isEvolutionPlaceholderPhone('+550001234567')).toBe(true);
      expect(isEvolutionPlaceholderPhone('+5511999999999')).toBe(false);
    });
  });

  describe('formatQrDataUrl', () => {
    it('prefixes raw base64 with a data URL', () => {
      expect(formatQrDataUrl('abc123')).toBe('data:image/png;base64,abc123');
    });

    it('returns data URLs unchanged', () => {
      const dataUrl = 'data:image/png;base64,abc123';
      expect(formatQrDataUrl(dataUrl)).toBe(dataUrl);
    });
  });

  describe('normalizeEvolutionConnectionPayload', () => {
    it('normalizes snake_case connection payloads', () => {
      expect(
        normalizeEvolutionConnectionPayload({
          connection_status: 'connecting',
          qrcode_base64: 'abc123',
          qrcode_code: '12345678',
          phone_number: '+5511999999999',
        })
      ).toEqual({
        connectionStatus: 'connecting',
        qrcodeBase64: 'data:image/png;base64,abc123',
        pairingCode: '1234-5678',
        phoneNumber: '+5511999999999',
      });
    });

    it('normalizes nested qrcode objects from webhooks', () => {
      const payload = normalizeEvolutionConnectionPayload({
        connection_status: 'connecting',
        qrcode: qrcodeWebhookPayload.qrcode,
      });

      expect(payload.connectionStatus).toBe('connecting');
      expect(payload.qrcodeBase64).toBe('data:image/png;base64,iVBORw0KGgo=');
    });

    it('ignores placeholder phone numbers', () => {
      expect(
        normalizeEvolutionConnectionPayload({
          connection_status: 'open',
          phone_number: '+550001234567',
        })
      ).toEqual({
        connectionStatus: 'open',
      });
    });

    it('normalizes camelCase API responses', () => {
      expect(
        normalizeEvolutionConnectionPayload({
          connectionStatus: 'open',
          phoneNumber: '+556681128433',
        })
      ).toEqual({
        connectionStatus: 'open',
        phoneNumber: '+556681128433',
      });
    });

    it('returns null for empty payloads', () => {
      expect(normalizeEvolutionConnectionPayload(null)).toBeNull();
      expect(normalizeEvolutionConnectionPayload({})).toBeNull();
    });
  });
});
