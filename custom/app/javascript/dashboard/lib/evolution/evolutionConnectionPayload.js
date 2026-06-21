function extractQrBase64(raw) {
  const direct = raw.qrcode_base64 || raw.qrcodeBase64;
  if (direct) return direct;

  const qrcode = raw.qrcode;
  if (!qrcode) return null;
  if (typeof qrcode === 'string') return qrcode;

  return qrcode?.qrcode?.base64 || qrcode?.base64 || null;
}

export function normalizeEvolutionConnectionPayload(raw) {
  if (!raw) return null;

  const payload = {};
  const status = raw.connection_status || raw.connectionStatus;
  if (status) payload.connectionStatus = status;

  const qr = extractQrBase64(raw);
  if (qr) payload.qrcodeBase64 = qr;

  return Object.keys(payload).length ? payload : null;
}
