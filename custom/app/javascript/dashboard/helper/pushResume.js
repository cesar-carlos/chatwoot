import Cookies from 'js-cookie';
import {
  isPushSessionActive,
  isCurrentPushSession,
  pushSession,
  startPushSession,
} from './pushSession';
import {
  ensurePushSubscription,
  getPushEnvironment,
} from 'customDashboard/helper/pushHelper';

export const BROWSER_PUSH_SYNC_EVENT = 'chatwoot:browser-push-sync';

export const syncBrowserPush = async () => {
  if (!isPushSessionActive()) return;
  const session = pushSession();
  try {
    const result = await ensurePushSubscription();
    if (!isCurrentPushSession(session)) return;
    window.dispatchEvent(
      new CustomEvent(BROWSER_PUSH_SYNC_EVENT, {
        detail: {
          status: result.status,
          permission: result.permission,
          cleanupError: Boolean(result.cleanupError),
          endpoint: result.subscription?.endpoint,
        },
      })
    );
  } catch (error) {
    if (!isCurrentPushSession(session)) return;
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

export const startBrowserPushResumeSync = () => {
  startPushSession();
  document.addEventListener('visibilitychange', syncWhenVisible);
};

export const stopBrowserPushResumeSync = () =>
  document.removeEventListener('visibilitychange', syncWhenVisible);
