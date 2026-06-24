import { describe, expect, it, vi } from 'vitest';
import {
  buildQrDataUrl,
  buildWavoipQrImageUrl,
  withCacheBust,
} from 'customDashboard/lib/wavoip/wavoipQrImage';

vi.mock('qrcode', () => ({
  default: {
    toDataURL: vi.fn(async value => `data:image/png;base64,mock-${value}`),
  },
}));

describe('wavoipQrImage', () => {
  it('buildQrDataUrl returns empty for blank input', async () => {
    await expect(buildQrDataUrl('')).resolves.toBe('');
    await expect(buildQrDataUrl(null)).resolves.toBe('');
  });

  it('buildQrDataUrl renders a data URL from the QR string', async () => {
    await expect(buildQrDataUrl('qr-payload')).resolves.toBe(
      'data:image/png;base64,mock-qr-payload'
    );
  });

  it('buildWavoipQrImageUrl encodes the device token', () => {
    expect(buildWavoipQrImageUrl('abc/token')).toBe(
      'https://devices.wavoip.com/abc%2Ftoken/whatsapp/qr-image'
    );
  });

  it('withCacheBust appends a timestamp query param', () => {
    expect(withCacheBust('https://example.com/qr')).toMatch(
      /^https:\/\/example.com\/qr\?t=\d+$/
    );
  });
});
