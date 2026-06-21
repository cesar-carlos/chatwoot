function extractQrBase64(raw) {
  const direct = raw.qrcode_base64 || raw.qrcodeBase64;
  if (direct) return direct;

  const qrcode = raw.qrcode;
  if (!qrcode) return null;
  if (typeof qrcode === 'string') return qrcode;

  return qrcode?.qrcode?.base64 || qrcode?.base64 || null;
}

function formatPairingCode(code) {
  if (!code) return null;
  const normalized = code.toString().replace(/\W/g, '');
  if (normalized.length === 8) {
    return `${normalized.slice(0, 4)}-${normalized.slice(4, 8)}`;
  }
  return code.toString();
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
  const direct = raw.qrcode_code || raw.qrcodeCode || raw.pairingCode;
  if (direct) return formatPairingCode(direct);

  const qrcode = raw.qrcode;
  if (!qrcode || typeof qrcode !== 'object') return null;

  return formatPairingCode(qrcode?.qrcode?.code || qrcode?.code);
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
