import { APIRequestContext, Page, expect } from '@playwright/test';

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

  buildEndedPayload(options: {
    whatsappCallId: string;
    callerDigits: string;
    receiverDigits: string;
    durationSeconds?: number;
  }): WavoipCallWebhookPayload & { duration?: number } {
    return {
      type: 'CALL',
      action: 'UPDATE',
      whatsapp_call_id: options.whatsappCallId,
      status: 'ENDED',
      direction: 'INCOMING',
      caller: options.callerDigits.replace(/\D/g, ''),
      receiver: options.receiverDigits.replace(/\D/g, ''),
      duration: options.durationSeconds ?? 0,
    };
  }

  async dismissInboundWidget(page: Page) {
    const dismiss = page.getByRole('button', { name: /dismiss/i }).first();
    await dismiss.click();
  }

  async waitForWidgetHidden(page: Page, options?: { timeoutMs?: number }) {
    const timeout = options?.timeoutMs ?? 15_000;
    await expect(page.getByText('Incoming call').first()).toBeHidden({ timeout });
  }

  /**
   * Polls for the inbound call widget after webhook POST (202).
   * Sidekiq must process Wavoip::ProcessWebhookJob before ActionCable delivers the event.
   */
  async waitForInboundWidget(
    page: Page,
    whatsappCallId: string,
    options?: { timeoutMs?: number }
  ) {
    const timeout = options?.timeoutMs ?? 45_000;

    await expect
      .poll(
        async () => page.getByText('Incoming call').first().isVisible(),
        {
          message: `Inbound widget not visible after webhook (call_id=${whatsappCallId}). Is Sidekiq running?`,
          timeout,
          intervals: [500, 1_000, 2_000, 3_000],
        }
      )
      .toBe(true);
  }
}
