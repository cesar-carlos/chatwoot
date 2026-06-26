import { test, expect } from '@playwright/test';
import { Login } from '@components/ui';
import { Auth, WavoipWebhookApi } from '@components/api';
import { accountIdFromUrl } from '@utils/auth';

const TEST_EMAIL = process.env.TEST_USER_EMAIL || 'admin@chatwoot.com';
const TEST_PASSWORD = process.env.TEST_USER_PASSWORD || 'Password123@#';
const WEBHOOK_KEY = process.env.WAVOIP_WEBHOOK_KEY || '';
const TEST_PEER_PHONE = process.env.WAVOIP_TEST_PEER_PHONE || '+5566999050312';
const INBOX_PHONE = process.env.WAVOIP_INBOX_PHONE || '';

function digitsOnly(phone: string) {
  return phone.replace(/\D/g, '');
}

async function setAvailabilityOnline(
  request: import('@playwright/test').APIRequestContext,
  accountId: string
) {
  const baseURL = process.env.BASE_URL || 'http://localhost:3000';
  const auth = new Auth(request, baseURL);
  const headers = await auth.login(TEST_EMAIL, TEST_PASSWORD);

  await request.put(`${baseURL.replace(/\/$/, '')}/api/v1/profile/availability`, {
    headers: {
      'Content-Type': 'application/json',
      Accept: 'application/json',
      ...headers,
    },
    data: {
      profile: {
        account_id: Number(accountId),
        availability: 'online',
      },
    },
  });
}

test.describe('Wavoip inbound call widget', () => {
  test.describe.configure({ timeout: 120_000 });

  test.beforeEach(() => {
    // eslint-disable-next-line playwright/no-skipped-test -- requires WAVOIP_WEBHOOK_KEY and WAVOIP_INBOX_PHONE
    test.skip(
      !WEBHOOK_KEY || !INBOX_PHONE,
      'Set WAVOIP_WEBHOOK_KEY and WAVOIP_INBOX_PHONE in tests/playwright/.env'
    );
  });

  test('shows FloatingCallWidget after inbound caller/receiver webhook', async ({
    page,
    request,
  }) => {
    const login = new Login(page);
    await login.navigate();
    await login.login(TEST_EMAIL, TEST_PASSWORD);
    await page.waitForURL(/\/app\/accounts\/\d+\//);

    const accountId = accountIdFromUrl(page.url());
    await setAvailabilityOnline(request, accountId);

    const receiverDigits = digitsOnly(INBOX_PHONE);

    const webhookApi = new WavoipWebhookApi(
      request,
      process.env.BASE_URL || 'http://localhost:3000'
    );
    await webhookApi.postCall(
      WEBHOOK_KEY,
      webhookApi.buildInboundCallerReceiverPayload({
        callerDigits: TEST_PEER_PHONE,
        receiverDigits,
      })
    );

    await expect(page.getByText('Incoming call').first()).toBeVisible({
      timeout: 45_000,
    });
  });
});
