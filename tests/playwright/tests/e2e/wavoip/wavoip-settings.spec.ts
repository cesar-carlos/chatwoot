import { test, expect } from '@playwright/test';
import { Login } from '@components/ui';
import { accountIdFromUrl } from '@utils/auth';

const TEST_EMAIL = process.env.TEST_USER_EMAIL || 'admin@chatwoot.com';
const TEST_PASSWORD = process.env.TEST_USER_PASSWORD || 'Password123@#';
const WAVOIP_INBOX_ID = process.env.WAVOIP_INBOX_ID || '';

test.describe('Wavoip inbox settings', () => {
  test.describe.configure({ timeout: 120_000 });

  test.beforeEach(() => {
    // eslint-disable-next-line playwright/no-skipped-test -- requires WAVOIP_INBOX_ID
    test.skip(
      !WAVOIP_INBOX_ID,
      'Set WAVOIP_INBOX_ID in tests/playwright/.env'
    );
  });

  test('shows webhook URL and device status on Calls tab', async ({ page }) => {
    const login = new Login(page);
    await login.navigate();
    await login.login(TEST_EMAIL, TEST_PASSWORD);
    await page.waitForURL(/\/app\/accounts\/\d+\//);

    const accountId = accountIdFromUrl(page.url());
    await page.goto(
      `/app/accounts/${accountId}/settings/inboxes/${WAVOIP_INBOX_ID}`
    );

    await page.getByRole('button', { name: 'Calls' }).click();

    await expect(page.getByText('Webhook URL')).toBeVisible();
    await expect(page.getByText(/\/webhooks\/wavoip\//)).toBeVisible();
    await expect(page.getByText('Device status')).toBeVisible();
    await expect(page.getByText('Business phone number')).toBeVisible();
  });
});
