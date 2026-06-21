import { APIRequestContext } from '@playwright/test';

export type AuthHeaders = Record<string, string>;

export class ApiClient {
  private pathValue = '';
  private headersValue: AuthHeaders = {};
  private bodyValue: unknown;
  private logRequests = false;

  constructor(
    private readonly request: APIRequestContext,
    private readonly baseURL: string
  ) {}

  path(path: string) {
    this.pathValue = path;
    return this;
  }

  headers(headers: AuthHeaders) {
    this.headersValue = { ...this.headersValue, ...headers };
    return this;
  }

  body(body: unknown) {
    this.bodyValue = body;
    return this;
  }

  logs(enabled: boolean) {
    this.logRequests = enabled;
    return this;
  }

  private url() {
    return `${this.baseURL.replace(/\/$/, '')}${this.pathValue}`;
  }

  private reset() {
    this.pathValue = '';
    this.headersValue = {};
    this.bodyValue = undefined;
    this.logRequests = false;
  }

  private async parseResponse(response: Awaited<ReturnType<APIRequestContext['get']>>) {
    const status = response.status();
    const text = await response.text();
    let data: unknown = null;

    if (text) {
      try {
        data = JSON.parse(text);
      } catch {
        data = text;
      }
    }

    return { status, data };
  }

  private async requestWithMethod(
    method: 'get' | 'post' | 'put' | 'delete',
    expectedStatus: number
  ) {
    const url = this.url();
    const options = {
      headers: {
        'Content-Type': 'application/json',
        Accept: 'application/json',
        ...this.headersValue,
      },
      data: this.bodyValue,
    };

    if (this.logRequests) {
      console.warn(`[api] ${method.toUpperCase()} ${url}`, this.bodyValue);
    }

    const response = await this.request[method](url, options);
    const { status, data } = await this.parseResponse(response);

    this.reset();

    if (status !== expectedStatus) {
      throw new Error(
        `Expected HTTP ${expectedStatus}, got ${status}: ${JSON.stringify(data)}`
      );
    }

    return data;
  }

  getRequest(expectedStatus = 200) {
    return this.requestWithMethod('get', expectedStatus);
  }

  postRequest(expectedStatus = 200) {
    return this.requestWithMethod('post', expectedStatus);
  }

  putRequest(expectedStatus = 200) {
    return this.requestWithMethod('put', expectedStatus);
  }

  deleteRequest(expectedStatus = 200) {
    return this.requestWithMethod('delete', expectedStatus);
  }
}
