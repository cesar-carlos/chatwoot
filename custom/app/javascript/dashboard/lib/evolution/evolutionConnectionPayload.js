function extractQrBase64(raw) {
  const direct = raw.qrcode_base64 || raw.qrcodeBase64;
  if (direct) return direct;

  const qrcode = raw.qrcode;
  if (!qrcode) return null;
  if (typeof qrcode === 'string') return qrcode;

  return qrcode?.qrcode?.base64 || qrcode?.base64 || null;
}

function isPairingCode(code) {
  if (!code) return false;
  return code.toString().replace(/\W/g, '').length === 8;
}

function formatPairingCode(code) {
  if (!code || !isPairingCode(code)) return null;
  const normalized = code.toString().replace(/\W/g, '');
  return `${normalized.slice(0, 4)}-${normalized.slice(4, 8)}`;
}

export function isEvolutionPlaceholderPhone(phone) {
  return phone?.toString().startsWith('+55000');
}

export function formatQrDataUrl(value) {
  if (!value) return '';
  if (value.startsWith('data:')) return value;

  return `data:image/png;base64,${value}`;
}

function extractPairingCode(raw) {
  const candidates = [
    raw.pairingCode,
    raw.qrcode_code,
    raw.qrcodeCode,
    raw.qrcode?.pairingCode,
    raw.qrcode?.qrcode?.pairingCode,
    raw.qrcode?.code,
    raw.qrcode?.qrcode?.code,
  ];

  return candidates.map(formatPairingCode).find(Boolean) || null;
}

export function normalizeEvolutionConnectionPayload(raw) {
  if (!raw) return null;

  const payload = {};
  const status = raw.connection_status || raw.connectionStatus;
  if (status) payload.connectionStatus = status;

  const qr = extractQrBase64(raw);
  if (qr) payload.qrcodeBase64 = formatQrDataUrl(qr);

  const pairingCode = extractPairingCode(raw);
  if (pairingCode) payload.pairingCode = pairingCode;

  const phone = raw.phone_number || raw.phoneNumber;
  if (phone && !isEvolutionPlaceholderPhone(phone)) {
    payload.phoneNumber = phone;
  }

  return Object.keys(payload).length ? payload : null;
}
