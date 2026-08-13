/**
 * Maps Chatwoot ICE servers (Call.default_ice_servers JSON) to the SDK
 * IceConfig: { iceServers?: RTCIceServer[], gatheringTimeoutMs?: number }.
 */
export function iceConfigFromBootstrap(data) {
  const servers = normalizeIceServers(data?.ice_servers || data?.iceServers);
  if (!servers.length) return undefined;
  return { iceServers: servers };
}

export function wavoipIceConfigKey(iceConfig) {
  if (!iceConfig?.iceServers?.length) return '';
  try {
    return JSON.stringify(iceConfig.iceServers);
  } catch (_) {
    return '';
  }
}

const normalizeIceServers = raw => {
  if (!Array.isArray(raw)) return [];

  return raw.flatMap(entry => {
    if (!entry || typeof entry !== 'object') return [];
    const urls = entry.urls || entry.url;
    if (urls == null || urls === '') return [];
    if (Array.isArray(urls) && urls.length === 0) return [];

    const server = { urls };
    if (entry.username) server.username = entry.username;
    if (entry.credential) server.credential = entry.credential;
    return [server];
  });
};
