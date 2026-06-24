import QRCode from 'qrcode';

export async function buildQrDataUrl(qrString) {
  if (!qrString?.trim()) return '';

  return QRCode.toDataURL(qrString.trim(), {
    width: 224,
    margin: 1,
  });
}

export function buildWavoipQrImageUrl(deviceToken) {
  if (!deviceToken) return '';

  return `https://devices.wavoip.com/${encodeURIComponent(deviceToken)}/whatsapp/qr-image`;
}

export function withCacheBust(url) {
  if (!url) return '';

  const separator = url.includes('?') ? '&' : '?';
  return `${url}${separator}t=${Date.now()}`;
}
