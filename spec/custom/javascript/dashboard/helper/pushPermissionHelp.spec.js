import { describe, expect, it } from 'vitest';
import { getPushPermissionHelpPlatform } from 'customDashboard/helper/pushPermissionHelp';

describe('notification permission help', () => {
  it.each([
    ['iPhone', 'iPhone', 1, 'IOS'],
    ['Safari', 'MacIntel', 5, 'IOS'],
    ['Chrome/140 Android', 'Linux', 1, 'ANDROID'],
    ['Chrome/140 Edg/140', 'Win32', 0, 'EDGE'],
    ['Chrome/140', 'Win32', 0, 'CHROME'],
    ['Firefox/140', 'Win32', 0, 'GENERIC'],
  ])(
    'selects %s platform instructions',
    (agent, platform, touches, expected) => {
      Object.defineProperty(navigator, 'userAgent', {
        configurable: true,
        value: agent,
      });
      Object.defineProperty(navigator, 'platform', {
        configurable: true,
        value: platform,
      });
      Object.defineProperty(navigator, 'maxTouchPoints', {
        configurable: true,
        value: touches,
      });
      expect(getPushPermissionHelpPlatform()).toBe(expected);
    }
  );
});
