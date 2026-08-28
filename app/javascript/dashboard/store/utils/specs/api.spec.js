import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import * as Sentry from '@sentry/vue';
import { closeAllDataManagers } from 'dashboard/helper/CacheHelper/DataManager';
import {
  getLoadingStatus,
  parseAPIErrorResponse,
  setLoadingStatus,
  throwErrorMessage,
  parseLinearAPIErrorResponse,
  deleteIndexedDBOnLogout,
  clearCookiesOnLogout,
  DELETE_DATABASE_BLOCKED_TIMEOUT_MS,
} from '../api';

vi.mock('@sentry/vue', () => ({
  setContext: vi.fn(),
  captureException: vi.fn(),
}));

vi.mock('dashboard/helper/CacheHelper/DataManager', () => ({
  closeAllDataManagers: vi.fn(),
}));

describe('#getLoadingStatus', () => {
  it('returns correct status', () => {
    expect(getLoadingStatus({ fetchAPIloadingStatus: true })).toBe(true);
  });
});

describe('#setLoadingStatus', () => {
  it('set correct status', () => {
    const state = { fetchAPIloadingStatus: true };
    setLoadingStatus(state, false);
    expect(state.fetchAPIloadingStatus).toBe(false);
  });
});

describe('#parseAPIErrorResponse', () => {
  it('returns correct values', () => {
    expect(
      parseAPIErrorResponse({
        response: { data: { message: 'Error Message [message]' } },
      })
    ).toBe('Error Message [message]');

    expect(
      parseAPIErrorResponse({
        response: { data: { error: 'Error Message [error]' } },
      })
    ).toBe('Error Message [error]');

    expect(parseAPIErrorResponse('Error: 422 Failed')).toBe(
      'Error: 422 Failed'
    );
  });
});

describe('#throwErrorMessage', () => {
  it('throws correct error', () => {
    const errorFn = function throwErrorMessageFn() {
      throwErrorMessage({
        response: { data: { message: 'Error Message [message]' } },
      });
    };
    expect(errorFn).toThrow('Error Message [message]');
  });
});

describe('#parseLinearAPIErrorResponse', () => {
  it('returns correct values', () => {
    expect(
      parseLinearAPIErrorResponse(
        {
          response: {
            data: {
              error: {
                errors: [
                  {
                    message: 'Error Message [message]',
                  },
                ],
              },
            },
          },
        },
        'Default Message'
      )
    ).toBe('Error Message [message]');
  });
});

describe('#deleteIndexedDBOnLogout', () => {
  const originalIndexedDB = global.window.indexedDB;

  beforeEach(() => {
    localStorage.setItem('cw-idb-names', JSON.stringify(['cw-store-1']));
  });

  afterEach(() => {
    global.window.indexedDB = originalIndexedDB;
    localStorage.clear();
  });

  it('awaits database deletion before resolving', async () => {
    const deleteDatabase = vi.fn(() => {
      const request = {
        onsuccess: null,
        onerror: null,
        onblocked: null,
      };
      queueMicrotask(() => request.onsuccess?.());
      return request;
    });

    global.window.indexedDB = {
      databases: vi.fn().mockResolvedValue([{ name: 'cw-store-1' }]),
      deleteDatabase,
    };

    await deleteIndexedDBOnLogout();

    expect(closeAllDataManagers).toHaveBeenCalled();
    expect(deleteDatabase).toHaveBeenCalledWith('cw-store-1');
    expect(localStorage.getItem('cw-idb-names')).toBeNull();
  });

  it('does not finish while deleteDatabase is blocked', async () => {
    vi.useFakeTimers();
    const deleteDatabase = vi.fn(() => {
      const request = {
        onsuccess: null,
        onerror: null,
        onblocked: null,
      };
      queueMicrotask(() => request.onblocked?.());
      return request;
    });

    global.window.indexedDB = {
      databases: vi.fn().mockResolvedValue([{ name: 'cw-store-1' }]),
      deleteDatabase,
    };

    const pending = deleteIndexedDBOnLogout();
    await Promise.resolve();
    await Promise.resolve();

    expect(localStorage.getItem('cw-idb-names')).toBe(
      JSON.stringify(['cw-store-1'])
    );
    expect(Sentry.captureException).not.toHaveBeenCalled();

    await vi.advanceTimersByTimeAsync(DELETE_DATABASE_BLOCKED_TIMEOUT_MS);
    await pending;

    expect(Sentry.captureException).toHaveBeenCalled();
    expect(localStorage.getItem('cw-idb-names')).toBeNull();
    vi.useRealTimers();
  });
});

describe('#clearCookiesOnLogout', () => {
  it('wipes IndexedDB before redirecting', async () => {
    const deleteDatabase = vi.fn(() => {
      const request = {
        onsuccess: null,
        onerror: null,
        onblocked: null,
      };
      queueMicrotask(() => request.onsuccess?.());
      return request;
    });

    global.window.indexedDB = {
      databases: vi.fn().mockResolvedValue([{ name: 'cw-store-12' }]),
      deleteDatabase,
    };

    delete window.location;
    window.location = '';

    await clearCookiesOnLogout();

    expect(deleteDatabase).toHaveBeenCalledWith('cw-store-12');
    expect(window.location).toBe('/');
  });
});
