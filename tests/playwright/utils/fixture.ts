import { test as base } from '@playwright/test';

import { ApiClient } from './api-client';

type Fixtures = {
  api: ApiClient;
};

export const test = base.extend<Fixtures>({
  api: async ({ request }, use) => {
    const baseURL = process.env.BASE_URL || 'http://localhost:3000';
    await use(new ApiClient(request, baseURL));
  },
});

export { expect } from '@playwright/test';
