let WavoipClass = null;

export async function loadWavoipSdk() {
  if (!WavoipClass) {
    ({ Wavoip: WavoipClass } = await import('@wavoip/wavoip-api'));
  }
  return WavoipClass;
}

export async function createWavoipClient({
  tokens,
  platform = 'chatwoot',
  iceConfig,
} = {}) {
  const Wavoip = await loadWavoipSdk();
  const params = { tokens, platform };
  if (iceConfig?.iceServers?.length) params.iceConfig = iceConfig;
  return new Wavoip(params);
}
