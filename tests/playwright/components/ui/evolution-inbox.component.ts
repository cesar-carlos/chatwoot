import { Page } from '@playwright/test';

export type EvolutionFormData = {
  inboxName: string;
  baseUrl: string;
  apiKey: string;
  instanceName: string;
};

export class EvolutionInbox {
  constructor(private readonly page: Page) {}

  async navigate(accountId: string) {
    await this.page.goto(
      `/app/accounts/${accountId}/settings/inboxes/new/whatsapp?provider=evolution`
    );
  }

  async fillForm(data: EvolutionFormData) {
    await this.page.getByLabel('Inbox Name').fill(data.inboxName);
    await this.page.getByLabel('Evolution API URL').fill(data.baseUrl);
    await this.page.getByLabel('API Key').fill(data.apiKey);
    await this.page.getByLabel('Instance name').fill(data.instanceName);
  }

  async submit() {
    await this.page
      .getByRole('button', { name: 'Create and show QR code' })
      .click();
  }

  getPageTitle() {
    return this.page.getByRole('heading', { name: 'Evolution API' });
  }

  getQrTitle() {
    return this.page.getByRole('heading', { name: 'Scan QR code' });
  }

  getQrLoadingMessage() {
    return this.page.getByText('Generating QR code…');
  }

  getErrorToast(message: string | RegExp) {
    return this.page.getByText(message);
  }
}
