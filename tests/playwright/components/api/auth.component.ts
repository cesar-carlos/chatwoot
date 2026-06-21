import { APIRequestContext } from '@playwright/test';

import { AuthHeaders } from '@utils/api-client';

export class Auth {
  constructor(
    private readonly request: APIRequestContext,
    private readonly baseURL: string
  ) {}

  async login(email: string, password: string): Promise<AuthHeaders> {
    const response = await this.request.post(
      `${this.baseURL.replace(/\/$/, '')}/auth/sign_in`,
      {
        headers: {
          'Content-Type': 'application/json',
          Accept: 'application/json',
        },
        data: { email, password },
      }
    );

    if (!response.ok()) {
      const body = await response.text();
      throw new Error(`Login failed (${response.status()}): ${body}`);
    }

    const headers = response.headers();

    return {
      'access-token': headers['access-token'] || '',
      client: headers['client'] || '',
      uid: headers['uid'] || '',
    };
  }
}
