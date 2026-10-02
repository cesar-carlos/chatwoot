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
let previousPermission;
let pendingSync;

export const publishBrowserPushState = result => {
  window.dispatchEvent(
    new CustomEvent(BROWSER_PUSH_SYNC_EVENT, {
      detail: {
        status: result.status,
        permission: result.permission,
        reason: result.reason,
        cleanupError: Boolean(result.cleanupError),
        endpoint: result.subscription?.endpoint,
      },
    })
  );
};

export const syncBrowserPush = () => {
  if (!isPushSessionActive()) return Promise.resolve();
  const session = pushSession();
  if (pendingSync && isCurrentPushSession(pendingSync.session))
    return pendingSync.promise;
  const permission = getPushEnvironment().permission;
  // Local pop-up permission must not implicitly opt this device into Push.
  const recoverPermission =
    previousPermission === 'denied' && permission === 'granted';
  previousPermission = permission;
  const operation = { session };
  pendingSync = operation;
  operation.promise = (async () => {
    try {
      const result = await ensurePushSubscription({ recoverPermission });
      if (!isCurrentPushSession(session)) return;
      publishBrowserPushState(result);
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
    } finally {
      if (pendingSync === operation) pendingSync = null;
    }
  })();
  return operation.promise;
};
const syncWhenVisible = () => {
  if (!document.hidden && Cookies.get('cw_d_session_info')) syncBrowserPush();
};

export const startBrowserPushResumeSync = () => {
  startPushSession();
  previousPermission = getPushEnvironment().permission;
  document.addEventListener('visibilitychange', syncWhenVisible);
  window.addEventListener('focus', syncWhenVisible);
};

export const stopBrowserPushResumeSync = () => {
  document.removeEventListener('visibilitychange', syncWhenVisible);
  window.removeEventListener('focus', syncWhenVisible);
};
