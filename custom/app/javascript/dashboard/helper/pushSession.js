import Cookies from 'js-cookie';

export const PUSH_OPERATION_TIMEOUT_MS = 10000;

let generation = 0;
let loggingOut = false;
const requests = new Set();

export const isPushSessionActive = () => !loggingOut;
export const pushSession = () => {
  if (loggingOut) throw new Error('Push session is ending');
  return { generation, identity: Cookies.get('cw_d_session_info') };
};
export const assertPushSession = session => {
  if (
    loggingOut ||
    session.generation !== generation ||
    session.identity !== Cookies.get('cw_d_session_info')
  ) {
    throw new Error('Push operation belongs to an expired session');
  }
};
export const isCurrentPushSession = session => {
  try {
    assertPushSession(session);
    return true;
  } catch (error) {
    return false;
  }
};
export const beginPushLogout = () => {
  loggingOut = true;
  generation += 1;
  requests.forEach(controller => controller.abort());
  requests.clear();
};
export const startPushSession = () => {
  if (loggingOut) generation += 1;
  loggingOut = false;
};
export const pushRequest = async operation => {
  const controller = new AbortController();
  requests.add(controller);
  const timeout = setTimeout(
    () => controller.abort(),
    PUSH_OPERATION_TIMEOUT_MS
  );
  try {
    return await operation({
      signal: controller.signal,
      timeout: PUSH_OPERATION_TIMEOUT_MS,
    });
  } finally {
    clearTimeout(timeout);
    requests.delete(controller);
  }
};
