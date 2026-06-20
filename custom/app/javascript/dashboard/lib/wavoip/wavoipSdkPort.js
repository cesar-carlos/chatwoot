let WavoipClass = null;

export async function loadWavoipSdk() {
  if (!WavoipClass) {
    ({ Wavoip: WavoipClass } = await import('@wavoip/wavoip-api'));
  }
  return WavoipClass;
}

export async function createWavoipClient({ tokens, platform = 'chatwoot' }) {
  const Wavoip = await loadWavoipSdk();
  return new Wavoip({ tokens, platform });
}
