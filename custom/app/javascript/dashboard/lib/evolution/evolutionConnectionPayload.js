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
    raw.pairing_code,
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

/** Seed health UI from inbox store data while the live status request runs. */
export function seedConnectionStateFromInbox(inbox) {
  if (!inbox) return {};

  const config = inbox.provider_config || {};
  const status = config.connection_status || config.connectionStatus;
  const phone = inbox.phone_number || config.phone_number || config.phoneNumber;

  const seeded = {};
  if (status) seeded.connectionStatus = status;
  if (phone && !isEvolutionPlaceholderPhone(phone)) {
    seeded.phoneNumber = phone;
  }
  return seeded;
}
