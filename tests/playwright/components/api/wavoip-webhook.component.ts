import { APIRequestContext } from '@playwright/test';

export type WavoipCallWebhookPayload = {
  type: 'CALL';
  action: 'CREATE' | 'create' | 'UPDATE' | 'update';
  whatsapp_call_id: string;
  status: string;
  direction: 'INCOMING' | 'OUTCOMING' | 'incoming' | 'outgoing';
  caller: string;
  receiver: string;
};

export class WavoipWebhookApi {
  constructor(
    private readonly request: APIRequestContext,
    private readonly baseURL: string
  ) {}

  async postCall(
    webhookKey: string,
    payload: WavoipCallWebhookPayload,
    expectedStatus = 202
  ) {
    const response = await this.request.post(
      `${this.baseURL.replace(/\/$/, '')}/webhooks/wavoip/${webhookKey}`,
      {
        headers: {
          'Content-Type': 'application/json',
          Accept: 'application/json',
        },
        data: payload,
      }
    );

    if (response.status() !== expectedStatus) {
      const body = await response.text();
      throw new Error(
        `Expected HTTP ${expectedStatus}, got ${response.status()}: ${body}`
      );
    }

    return response;
  }

  buildInboundCallerReceiverPayload(options: {
    callerDigits: string;
    receiverDigits: string;
    whatsappCallId?: string;
  }): WavoipCallWebhookPayload {
    return {
      type: 'CALL',
      action: 'CREATE',
      whatsapp_call_id:
        options.whatsappCallId ||
        `playwright_inbound_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`,
      status: 'INCOMING_RING',
      direction: 'INCOMING',
      caller: options.callerDigits.replace(/\D/g, ''),
      receiver: options.receiverDigits.replace(/\D/g, ''),
    };
  }
}
