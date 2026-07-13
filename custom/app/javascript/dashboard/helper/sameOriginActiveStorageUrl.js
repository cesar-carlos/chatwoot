/**
 * Active Storage blob URLs are absolute and use FRONTEND_URL (canonical host).
 * When the dashboard is opened via an alias host (e.g. dev-chat.*), downloadFile
 * fetch() becomes cross-origin and fails without CORS on /rails/active_storage/*.
 *
 * Rewrite only Active Storage paths to the current origin so fetch stays same-origin.
 * External URLs (Instagram, S3 direct, etc.) are left unchanged.
 */
export const toSameOriginActiveStorageUrl = url => {
  if (!url || typeof url !== 'string') return url;

  try {
    const parsed = new URL(url, window.location.origin);
    if (!parsed.pathname.includes('/rails/active_storage/')) return url;
    if (parsed.origin === window.location.origin) return url;

    return `${window.location.origin}${parsed.pathname}${parsed.search}${parsed.hash}`;
  } catch {
    return url;
  }
};
