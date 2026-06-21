import { Auth, EvolutionInboxApi } from '@components/api';
import { evolutionConfig, hasEvolutionCredentials } from '@utils/evolution-config';
import { expect, test } from '@utils/fixture';
import { fake } from '@utils/test-data';
import { AuthHeaders } from '@utils/api-client';

const TEST_EMAIL = process.env.TEST_USER_EMAIL || 'admin@chatwoot.com';
const TEST_PASSWORD = process.env.TEST_USER_PASSWORD || 'Password123@#';
const INVALID_API_KEY = '429683C4C977415CAAFCCE10F7D57E11';

test.describe('Evolution inbox API', () => {
  test.describe.configure({ timeout: 120_000 });

  let authHeaders: AuthHeaders;

  test.beforeAll(async ({ request }) => {
    const baseURL = process.env.BASE_URL || 'http://localhost:3000';
    authHeaders = await new Auth(request, baseURL).login(
      TEST_EMAIL,
      TEST_PASSWORD
    );
  });

  test('rejects invalid Evolution API key', async ({ api }) => {
    const evolutionInboxApi = new EvolutionInboxApi(api);
    // eslint-disable-next-line playwright/no-skipped-test -- requires external Evolution URL
    test.skip(
      !evolutionConfig.baseUrl,
      'Set EVOLUTION_BASE_URL in tests/playwright/.env'
    );

    const response = (await evolutionInboxApi.create(
      authHeaders,
      evolutionConfig.accountId,
      {
        name: fake.inboxName(),
        baseUrl: evolutionConfig.baseUrl,
        apiKey: INVALID_API_KEY,
        instanceName: fake.evolutionInstanceName('e2e-invalid-key'),
      },
      422
    )) as { message?: string };

    expect(response.message).toBeTruthy();
  });

  test('creates Evolution inbox and returns connection payload', async ({
    api,
  }) => {
    // eslint-disable-next-line playwright/no-skipped-test -- requires Evolution credentials
    test.skip(
      !hasEvolutionCredentials(),
      'Set EVOLUTION_BASE_URL and EVOLUTION_API_KEY in tests/playwright/.env'
    );

    const inboxApi = new EvolutionInboxApi(api);
    const instanceName = fake.evolutionInstanceName('e2e');
    const inboxName = fake.inboxName();

    const inbox = await inboxApi.create(
      authHeaders,
      evolutionConfig.accountId,
      {
        name: inboxName,
        baseUrl: evolutionConfig.baseUrl,
        apiKey: evolutionConfig.apiKey,
        instanceName,
      }
    );

    expect(inbox.id).toBeTruthy();
    expect(inbox.name).toBe(inboxName);

    const connection = await inboxApi.getConnection(
      authHeaders,
      evolutionConfig.accountId,
      inbox.id
    );

    const status =
      connection.connection_status || connection.connectionStatus || '';

    expect(status).toBeTruthy();
    expect(
      connection.qrcode_base64 ||
        connection.qrcodeBase64 ||
        connection.pairing_code ||
        connection.pairingCode
    ).toBeTruthy();

    await inboxApi.delete(authHeaders, evolutionConfig.accountId, inbox.id);
  });
});
