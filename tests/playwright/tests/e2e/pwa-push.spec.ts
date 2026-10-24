import { test, expect } from '@playwright/test';

declare global {
  interface Window {
    __e2ePush?: { count: number };
  }
}

import { loginViaUi } from '../../utils/auth';

const email = process.env.TEST_USER_EMAIL || 'admin@chatwoot.com';
const password = process.env.TEST_USER_PASSWORD || 'Password123@#';

// Real delivery to a phone stays a manual check. Headless Chromium cannot
// reach the push service, so subscribe is simulated and the API is stubbed.
// Run on demand: PWA_E2E=1 pnpm exec playwright test tests/e2e/pwa-push.spec.ts
test.describe('PWA browser push reinstall', () => {
  test.skip(
    process.env.PWA_E2E !== '1',
    'On-demand only. Real device delivery is still checked by hand.'
  );

  test('activates, signs out and subscribes again without an opt-out', async ({
    page,
    context,
  }) => {
    await context.grantPermissions(['notifications']);
    await context.addInitScript(() => {
      const state = { count: 0, current: null as null | Record<string, unknown> };
      const build = () => ({
        endpoint: 'https://push.example.test/e2e-device',
        options: {},
        getKey: () => new Uint8Array(16).buffer,
        unsubscribe: async () => {
          state.current = null;
          return true;
        },
      });
      Object.assign(window, { __e2ePush: state });
      if (!window.PushManager) return;
      window.PushManager.prototype.subscribe = async function subscribe() {
        state.count += 1;
        state.current = build();
        return state.current;
      };
      window.PushManager.prototype.getSubscription = async function getSubscription() {
        return state.current;
      };
    });
    await page.route('**/api/v1/notification_subscriptions**', async route => {
      const method = route.request().method();
      if (method === 'POST' || method === 'DELETE') {
        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: '{}',
        });
        return;
      }
      await route.continue();
    });

    await page.goto('/app/login');
    await expect(page.locator('link[rel="manifest"]')).toHaveAttribute(
      'href',
      '/manifest.webmanifest'
    );

    await loginViaUi(page, email, password);
    const worker = await page.evaluate(async () => {
      const registration = await navigator.serviceWorker.register('/sw.js', {
        updateViaCache: 'none',
      });
      return Boolean(registration.active || registration.installing || registration.waiting);
    });
    expect(worker).toBe(true);

    const accountId = page.url().match(/\/app\/accounts\/(\d+)\//)?.[1];
    expect(accountId).toBeTruthy();
    await page.goto(
      `/app/accounts/${accountId}/profile/settings#profile-settings-notifications`
    );
    await page.getByRole('button', { name: 'Activate on this device' }).click();
    await expect
      .poll(() => page.evaluate(() => window.__e2ePush?.count ?? 0))
      .toBeGreaterThan(0);

    const preference = await page.evaluate(() => {
      const raw = document.cookie
        .split('; ')
        .find(item => item.startsWith('cw_d_session_info='))
        ?.slice('cw_d_session_info='.length);
      const uid = raw ? JSON.parse(decodeURIComponent(raw)).uid : null;
      const key = uid ? `chatwoot:push-enabled:v1:${uid}` : null;
      return {
        key,
        value: key ? localStorage.getItem(key) : null,
        legacy: localStorage.getItem('chatwoot_push_enabled'),
      };
    });
    expect(preference.value).toBe('true');
    expect(preference.legacy).not.toBe('false');

    await page.getByRole('button', { name: email }).click();
    await page.getByRole('button', { name: 'Log out' }).click();
    await page.waitForURL(/\/app\/login/);
    const afterLogout = await page.evaluate(key => {
      return {
        value: key ? localStorage.getItem(key) : null,
        legacy: localStorage.getItem('chatwoot_push_enabled'),
      };
    }, preference.key);
    expect(afterLogout.value).toBe('true');
    expect(afterLogout.legacy).not.toBe('false');

    await loginViaUi(page, email, password);
    await expect
      .poll(() => page.evaluate(() => window.__e2ePush?.count ?? 0))
      .toBeGreaterThan(1);
  });
});
