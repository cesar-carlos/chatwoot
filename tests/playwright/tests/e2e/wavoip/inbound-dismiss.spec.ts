import { test } from '@playwright/test';
import { Login } from '@components/ui';
import { Auth, WavoipWebhookApi } from '@components/api';
import { accountIdFromUrl } from '@utils/auth';

const TEST_EMAIL = process.env.TEST_USER_EMAIL || 'admin@chatwoot.com';
const TEST_PASSWORD = process.env.TEST_USER_PASSWORD || '';
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

test.describe('Wavoip inbound dismiss (gate F1)', () => {
  test.describe.configure({ timeout: 120_000 });

  test.beforeEach(() => {
    test.skip(
      !WEBHOOK_KEY || !INBOX_PHONE || !TEST_PASSWORD,
      'Set WAVOIP_WEBHOOK_KEY, WAVOIP_INBOX_PHONE and TEST_USER_PASSWORD in tests/playwright/.env'
    );
  });

  test('agent dismiss removes the inbound widget without accepting', async ({
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
    const baseURL = process.env.BASE_URL || 'http://localhost:3000';
    const webhookApi = new WavoipWebhookApi(request, baseURL);
    const payload = webhookApi.buildInboundCallerReceiverPayload({
      callerDigits: TEST_PEER_PHONE,
      receiverDigits,
    });

    await webhookApi.postCall(WEBHOOK_KEY, payload);
    await webhookApi.waitForInboundWidget(page, payload.whatsapp_call_id);
    await webhookApi.dismissInboundWidget(page);
    await webhookApi.waitForWidgetHidden(page);
  });
});
