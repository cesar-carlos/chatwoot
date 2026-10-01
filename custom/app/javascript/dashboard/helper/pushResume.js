import Cookies from 'js-cookie';
import {
  ensurePushSubscription,
  getPushEnvironment,
} from 'customDashboard/helper/pushHelper';

export const BROWSER_PUSH_SYNC_EVENT = 'chatwoot:browser-push-sync';

export const syncBrowserPush = async () => {
  try {
    const result = await ensurePushSubscription();
    window.dispatchEvent(
      new CustomEvent(BROWSER_PUSH_SYNC_EVENT, {
        detail: {
          status: result.status,
          permission: result.permission,
          cleanupError: Boolean(result.cleanupError),
        },
      })
    );
  } catch (error) {
    window.dispatchEvent(
      new CustomEvent(BROWSER_PUSH_SYNC_EVENT, {
        detail: {
          status: 'error',
          permission: getPushEnvironment().permission,
        },
      })
    );
    // eslint-disable-next-line no-console
    console.error('Push subscription synchronization failed');
  }
};

const syncWhenVisible = () => {
  if (!document.hidden && Cookies.get('cw_d_session_info')) syncBrowserPush();
};

export const startBrowserPushResumeSync = () =>
  document.addEventListener('visibilitychange', syncWhenVisible);

export const stopBrowserPushResumeSync = () =>
  document.removeEventListener('visibilitychange', syncWhenVisible);
