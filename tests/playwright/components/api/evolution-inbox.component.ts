import { ApiClient, AuthHeaders } from '@utils/api-client';

export type EvolutionInboxPayload = {
  name: string;
  baseUrl: string;
  apiKey: string;
  instanceName: string;
};

export type EvolutionInboxResponse = {
  id: number;
  name: string;
  channel_type?: string;
  provider?: string;
};

export type EvolutionConnectionResponse = {
  connection_status?: string;
  connectionStatus?: string;
  qrcode_base64?: string;
  qrcodeBase64?: string;
  pairing_code?: string;
  pairingCode?: string;
};

export class EvolutionInboxApi {
  constructor(private readonly api: ApiClient) {}

  buildCreateBody(payload: EvolutionInboxPayload) {
    return {
      name: payload.name,
      channel: {
        type: 'whatsapp',
        provider: 'evolution',
        base_url: payload.baseUrl.replace(/\/$/, ''),
        api_key: payload.apiKey,
        instance_name: payload.instanceName,
        provider_config: {
          proxy_enabled: false,
        },
      },
    };
  }

  create(
    authHeaders: AuthHeaders,
    accountId: string,
    payload: EvolutionInboxPayload,
    expectedStatus = 200
  ) {
    return this.api
      .path(`/api/v1/accounts/${accountId}/inboxes`)
      .headers(authHeaders)
      .body(this.buildCreateBody(payload))
      .postRequest(expectedStatus) as Promise<EvolutionInboxResponse>;
  }

  getConnection(
    authHeaders: AuthHeaders,
    accountId: string,
    inboxId: number | string
  ) {
    return this.api
      .path(
        `/api/v1/accounts/${accountId}/inboxes/${inboxId}/evolution_connection`
      )
      .headers(authHeaders)
      .getRequest(200) as Promise<EvolutionConnectionResponse>;
  }

  delete(authHeaders: AuthHeaders, accountId: string, inboxId: number | string) {
    return this.api
      .path(`/api/v1/accounts/${accountId}/inboxes/${inboxId}`)
      .headers(authHeaders)
      .deleteRequest(200);
  }
}
