import { beforeEach, describe, expect, it, vi } from 'vitest';

const clearWavoipMediaForInbox = vi.fn();

vi.mock('customDashboard/lib/wavoip/wavoipSdkPort', () => ({
  createWavoipClient: vi.fn().mockResolvedValue({ removeDevices: vi.fn() }),
}));

vi.mock('customDashboard/composables/wavoip/useWavoipMedia', () => ({
  clearWavoipMediaForInbox: (...args) => clearWavoipMediaForInbox(...args),
}));

import { createWavoipClient } from 'customDashboard/lib/wavoip/wavoipSdkPort';
import {
  connectWavoipInbox,
  disconnectWavoipInbox,
} from '../wavoipClientRegistry';

describe('wavoipClientRegistry', () => {
  beforeEach(() => {
    clearWavoipMediaForInbox.mockReset();
    createWavoipClient.mockReset();
    createWavoipClient.mockResolvedValue({ removeDevices: vi.fn() });
  });

  it('clears media state when disconnecting an inbox', async () => {
    const removeDevices = vi.fn();
    createWavoipClient.mockResolvedValue({ removeDevices });

    await connectWavoipInbox(7, 'token-7');
    await disconnectWavoipInbox(7);

    expect(clearWavoipMediaForInbox).toHaveBeenCalledWith(7);
    expect(removeDevices).toHaveBeenCalledWith(['token-7']);
  });

  it('passes ICE servers from bootstrap into the SDK client', async () => {
    const iceConfig = {
      iceServers: [{ urls: 'stun:stun.l.google.com:19302' }],
    };
    await connectWavoipInbox(8, 'token-8', { iceConfig });

    expect(createWavoipClient).toHaveBeenCalledWith({
      tokens: ['token-8'],
      iceConfig,
    });
  });
});
