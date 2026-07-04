import { beforeEach, describe, expect, it, vi } from 'vitest';
import wootConstants from 'dashboard/constants/globals';

const toggleStatus = vi.fn().mockResolvedValue({
  data: { payload: { current_status: 'pending' } },
});
const setChatStatusFilter = vi.fn();

vi.mock('dashboard/store', () => ({
  default: {
    getters: {
      getConversationById: () => () => ({ id: 42, status: 'resolved' }),
    },
    dispatch: vi.fn((action, payload) => {
      if (action === 'toggleStatus') return toggleStatus(payload);
      if (action === 'setChatStatusFilter') return setChatStatusFilter(payload);
      return Promise.resolve();
    }),
  },
}));

import { reopenWavoipInboundConversation } from '../wavoipInboundConversation';

describe('reopenWavoipInboundConversation', () => {
  beforeEach(() => {
    toggleStatus.mockClear();
    setChatStatusFilter.mockClear();
  });

  it('reopens resolved conversations as pending and switches the inbox filter', async () => {
    await reopenWavoipInboundConversation(42);

    expect(toggleStatus).toHaveBeenCalledWith({
      conversationId: 42,
      status: wootConstants.STATUS_TYPE.PENDING,
    });
    expect(setChatStatusFilter).toHaveBeenCalledWith(
      wootConstants.STATUS_TYPE.PENDING
    );
  });

  it('no-ops without a conversation id', async () => {
    await reopenWavoipInboundConversation(null);
    expect(toggleStatus).not.toHaveBeenCalled();
  });
});
