import { Page } from '@playwright/test';

import { Login } from '@components/ui';

export async function loginViaUi(page: Page, email: string, password: string) {
  const login = new Login(page);
  await login.navigate();
  await login.login(email, password);
  await page.waitForURL(/\/app\/accounts\/\d+\//);
}

export function accountIdFromUrl(url: string, fallback = '1') {
  const match = url.match(/\/app\/accounts\/(\d+)\//);
  return match?.[1] || fallback;
}
