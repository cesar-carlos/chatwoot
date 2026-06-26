import { beforeEach, describe, expect, it, vi } from 'vitest';

const clearWavoipMediaForInbox = vi.fn();

vi.mock('customDashboard/lib/wavoip/wavoipSdkPort', () => ({
  createWavoipClient: vi.fn().mockResolvedValue({ removeDevices: vi.fn() }),
}));

vi.mock('customDashboard/composables/wavoip/useWavoipMedia', () => ({
  clearWavoipMediaForInbox: (...args) => clearWavoipMediaForInbox(...args),
}));

import {
  connectWavoipInbox,
  disconnectWavoipInbox,
} from '../wavoipClientRegistry';

describe('wavoipClientRegistry', () => {
  beforeEach(() => {
    clearWavoipMediaForInbox.mockReset();
  });

  it('clears media state when disconnecting an inbox', async () => {
    await connectWavoipInbox(7, 'token-7');
    await disconnectWavoipInbox(7);

    expect(clearWavoipMediaForInbox).toHaveBeenCalledWith(7);
  });
});
