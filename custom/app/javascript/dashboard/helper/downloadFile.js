import { downloadFile as downloadFileFromUtils } from '@chatwoot/utils';
import { toSameOriginActiveStorageUrl } from './sameOriginActiveStorageUrl';

/**
 * Same as @chatwoot/utils downloadFile, but rewrites Active Storage URLs to the
 * current origin so alias hosts (dev-chat) can download without CORS errors.
 */
export const downloadFile = ({ url, type, extension = null }) =>
  downloadFileFromUtils({
    url: toSameOriginActiveStorageUrl(url),
    type,
    extension,
  });
