import { Login, EvolutionInbox } from '@components/ui';
import { EvolutionInboxApi } from '@components/api';
import { evolutionConfig, hasEvolutionCredentials } from '@utils/evolution-config';
import { accountIdFromUrl } from '@utils/auth';
import { fake } from '@utils/test-data';
import { expect, test } from '@utils/fixture';

const TEST_EMAIL = process.env.TEST_USER_EMAIL || 'admin@chatwoot.com';
const TEST_PASSWORD = process.env.TEST_USER_PASSWORD || 'Password123@#';
const INVALID_API_KEY = '429683C4C977415CAAFCCE10F7D57E11';

test.describe('Evolution inbox UI', () => {
  test.describe.configure({ timeout: 120_000 });

  let accountId: string;
  let createdInboxId: number | null = null;
  let authHeaders: Awaited<ReturnType<Login['login']>> | null = null;

  test.beforeEach(async ({ page }) => {
    const login = new Login(page);
    await login.navigate();
    authHeaders = await login.login(TEST_EMAIL, TEST_PASSWORD);
    await page.waitForURL(/\/app\/accounts\/\d+\//);
    accountId = accountIdFromUrl(page.url(), evolutionConfig.accountId);
    createdInboxId = null;
  });

  test.afterEach(async ({ api }) => {
    if (!createdInboxId || !authHeaders) return;

    const inboxApi = new EvolutionInboxApi(api);
    await inboxApi.delete(authHeaders, accountId, createdInboxId);
    createdInboxId = null;
  });

  test('renders Evolution form fields', async ({ page }) => {
    const evolutionInbox = new EvolutionInbox(page);
    await evolutionInbox.navigate(accountId);

    await expect(evolutionInbox.getPageTitle()).toBeVisible();
    await expect(page.getByLabel('Inbox Name')).toBeVisible();
    await expect(page.getByLabel('Evolution API URL')).toBeVisible();
    await expect(page.getByLabel('API Key')).toBeVisible();
    await expect(page.getByLabel('Instance name')).toBeVisible();
    await expect(
      page.getByRole('button', { name: 'Create and show QR code' })
    ).toBeDisabled();
  });

  test('shows error for invalid API key', async ({ page }) => {
    // eslint-disable-next-line playwright/no-skipped-test -- requires external Evolution URL
    test.skip(
      !evolutionConfig.baseUrl,
      'Set EVOLUTION_BASE_URL in tests/playwright/.env'
    );

    const evolutionInbox = new EvolutionInbox(page);
    await evolutionInbox.navigate(accountId);
    await evolutionInbox.fillForm({
      inboxName: fake.inboxName(),
      baseUrl: evolutionConfig.baseUrl,
      apiKey: INVALID_API_KEY,
      instanceName: fake.evolutionInstanceName('e2e-ui-invalid'),
    });
    await evolutionInbox.submit();

    await expect(
      evolutionInbox.getErrorToast(/Could not create the Evolution inbox|Unauthorized|Invalid|Failed/i)
    ).toBeVisible({ timeout: 60_000 });
  });

  test('creates inbox and shows QR step', async ({ page, api }) => {
    // eslint-disable-next-line playwright/no-skipped-test -- requires Evolution credentials
    test.skip(
      !hasEvolutionCredentials(),
      'Set EVOLUTION_BASE_URL and EVOLUTION_API_KEY in tests/playwright/.env'
    );

    page.on('response', async response => {
      if (
        response.request().method() === 'POST' &&
        /\/api\/v1\/accounts\/\d+\/inboxes$/.test(response.url()) &&
        response.ok()
      ) {
        const body = (await response.json()) as { id?: number };
        createdInboxId = body.id ?? null;
      }
    });

    const evolutionInbox = new EvolutionInbox(page);
    await evolutionInbox.navigate(accountId);
    await evolutionInbox.fillForm({
      inboxName: fake.inboxName(),
      baseUrl: evolutionConfig.baseUrl,
      apiKey: evolutionConfig.apiKey,
      instanceName: fake.evolutionInstanceName('e2e-ui'),
    });
    await evolutionInbox.submit();

    await expect(evolutionInbox.getQrTitle()).toBeVisible({ timeout: 60_000 });
    await expect(
      page.getByAltText('WhatsApp QR Code').or(evolutionInbox.getQrLoadingMessage())
    ).toBeVisible({ timeout: 60_000 });
    expect(createdInboxId).toBeTruthy();
  });
});
