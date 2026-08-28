import fromUnixTime from 'date-fns/fromUnixTime';
import differenceInDays from 'date-fns/differenceInDays';
import Cookies from 'js-cookie';
import * as Sentry from '@sentry/vue';
import { LOCAL_STORAGE_KEYS } from 'dashboard/constants/localStorage';
import { SESSION_STORAGE_KEYS } from 'dashboard/constants/sessionStorage';
import { closeAllDataManagers } from 'dashboard/helper/CacheHelper/DataManager';
import { LocalStorage } from 'shared/helpers/localStorage';
import SessionStorage from 'shared/helpers/sessionStorage';
import { emitter } from 'shared/helpers/mitt';
import {
  ANALYTICS_IDENTITY,
  ANALYTICS_RESET,
  CHATWOOT_RESET,
  CHATWOOT_SET_USER,
} from '../../constants/appEvents';

Cookies.defaults = { sameSite: 'Lax' };

export const getLoadingStatus = state => state.fetchAPIloadingStatus;
export const setLoadingStatus = (state, status) => {
  state.fetchAPIloadingStatus = status;
};

export const setUser = user => {
  emitter.emit(CHATWOOT_SET_USER, { user });
  emitter.emit(ANALYTICS_IDENTITY, { user });
};

export const getHeaderExpiry = response =>
  fromUnixTime(response.headers.expiry);

export const setAuthCredentials = response => {
  const expiryDate = getHeaderExpiry(response);
  Cookies.set('cw_d_session_info', JSON.stringify(response.headers), {
    expires: differenceInDays(expiryDate, new Date()),
  });
  setUser(response.data.data, expiryDate);
};

export const clearBrowserSessionCookies = () => {
  Cookies.remove('cw_d_session_info');
  Cookies.remove('auth_data');
  Cookies.remove('user');
};

export const clearLocalStorageOnLogout = () => {
  LocalStorage.remove(LOCAL_STORAGE_KEYS.DRAFT_MESSAGES);
};

export const clearSessionStorageOnLogout = () => {
  SessionStorage.remove(SESSION_STORAGE_KEYS.IMPERSONATION_USER);
};

export const DELETE_DATABASE_BLOCKED_TIMEOUT_MS = 3000;

const reportIndexedDBCleanupFailure = (dbName, event, reason) => {
  Sentry.setContext('IndexedDBCleanup', { dbName, reason });
  Sentry.captureException(
    event?.target?.error || new Error(`IndexedDB ${reason}: ${dbName}`)
  );
};

const deleteDatabase = dbName =>
  new Promise(resolve => {
    if (!dbName) {
      resolve();
      return;
    }

    const deleteRequest = window.indexedDB.deleteDatabase(dbName);
    let settled = false;
    let blockedTimeout;

    const finish = () => {
      if (settled) return;
      settled = true;
      clearTimeout(blockedTimeout);
      resolve();
    };

    deleteRequest.onsuccess = () => finish();
    deleteRequest.onerror = event => {
      reportIndexedDBCleanupFailure(dbName, event, 'onerror');
      finish();
    };
    // FORK: onblocked is not success — wait for onsuccess after connections close
    deleteRequest.onblocked = () => {
      blockedTimeout = setTimeout(() => {
        reportIndexedDBCleanupFailure(dbName, null, 'onblocked_timeout');
        finish();
      }, DELETE_DATABASE_BLOCKED_TIMEOUT_MS);
    };
  });

export const deleteIndexedDBOnLogout = async () => {
  closeAllDataManagers();

  let dbs = [];
  try {
    dbs = await window.indexedDB.databases();
    dbs = dbs.map(db => db.name).filter(Boolean);
  } catch (e) {
    dbs = JSON.parse(localStorage.getItem('cw-idb-names') || '[]');
  }

  // FORK: wait for each deleteDatabase so the next login cannot reuse a stale account cache
  await Promise.all(dbs.map(deleteDatabase));

  localStorage.removeItem('cw-idb-names');
};

export const clearCookiesOnLogout = async () => {
  await deleteIndexedDBOnLogout();
  emitter.emit(CHATWOOT_RESET);
  emitter.emit(ANALYTICS_RESET);
  clearBrowserSessionCookies();
  clearLocalStorageOnLogout();
  clearSessionStorageOnLogout();
  const globalConfig = window.globalConfig || {};
  const logoutRedirectLink = globalConfig.LOGOUT_REDIRECT_LINK || '/';
  window.location = logoutRedirectLink;
};

export const parseAPIErrorResponse = error => {
  if (error?.response?.data?.message) {
    return error?.response?.data?.message;
  }
  if (error?.response?.data?.error) {
    return error?.response?.data?.error;
  }
  if (error?.response?.data?.errors) {
    return error?.response?.data?.errors[0];
  }
  return error;
};

export const throwErrorMessage = error => {
  const errorMessage = parseAPIErrorResponse(error);
  throw new Error(errorMessage);
};

export const parseLinearAPIErrorResponse = (error, defaultMessage) => {
  const errorData = error.response.data;
  const errorMessage = errorData?.error?.errors?.[0]?.message || defaultMessage;
  return errorMessage;
};
