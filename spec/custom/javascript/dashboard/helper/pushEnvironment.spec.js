import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { getPushEnvironment } from 'customDashboard/helper/pushHelper';

describe('specific Push environment diagnosis', () => {
  beforeEach(() => {
    vi.stubGlobal('navigator', {
      userAgent: 'Chrome Android',
      platform: 'Linux',
      maxTouchPoints: 0,
      standalone: false,
      serviceWorker: {},
    });
    vi.stubGlobal('Notification', { permission: 'granted' });
    vi.stubGlobal('PushManager', class PushManager {});
    Object.defineProperty(window, 'isSecureContext', {
      configurable: true,
      value: true,
    });
    window.chatwootConfig = { vapidPublicKey: 'configured-public-key' };
    vi.spyOn(window, 'matchMedia').mockReturnValue({ matches: false });
  });
  afterEach(() => {
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
  });

  it('preserves the supported environment contract', () => {
    expect(getPushEnvironment()).toEqual({
      supported: true,
      permission: 'granted',
      status: 'granted',
    });
  });
  it('identifies an insecure context without misreporting user permission', () => {
    Object.defineProperty(window, 'isSecureContext', {
      configurable: true,
      value: false,
    });
    expect(getPushEnvironment()).toMatchObject({
      supported: false,
      permission: 'granted',
      reason: 'insecure_context',
    });
  });
  it('distinguishes missing server configuration and does not expose key data', () => {
    window.chatwootConfig = {};
    expect(getPushEnvironment()).toEqual({
      supported: false,
      permission: 'granted',
      status: 'unsupported',
      reason: 'missing_configuration',
    });
  });
  it.each(['Notification', 'PushManager', 'serviceWorker'])(
    'identifies a missing browser API (%s)',
    name => {
      if (name === 'serviceWorker') delete navigator.serviceWorker;
      else vi.stubGlobal(name, undefined);
      // The helper checks API presence, not a user-agent allowlist.
      if (name !== 'serviceWorker') delete window[name];
      expect(getPushEnvironment()).toMatchObject({
        supported: false,
        reason: 'unsupported_browser',
      });
    }
  );
  it('keeps iOS installation requirements distinct from incompatibility', () => {
    navigator.userAgent = 'iPhone';
    expect(getPushEnvironment()).toEqual({
      supported: false,
      permission: 'granted',
      status: 'requires_install',
    });
  });
});
