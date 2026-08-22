import { beforeEach, describe, expect, it, vi } from 'vitest';

const { mockUnsubscribe, subscriptions, createConsumer } = vi.hoisted(() => {
  const unsub = vi.fn();
  const subs = {
    create: vi.fn(() => ({ unsubscribe: unsub })),
  };
  const consumer = vi.fn(() => ({
    subscriptions: subs,
    disconnect: vi.fn(),
  }));
  return {
    mockUnsubscribe: unsub,
    subscriptions: subs,
    createConsumer: consumer,
  };
});

vi.mock('@rails/actioncable', () => ({
  createConsumer,
}));

import {
  acquireEvolutionConnectionCable,
  onEvolutionConnectionClosed,
} from 'customDashboard/lib/evolution/evolutionCableRegistry';

describe('evolutionCableRegistry', () => {
  const context = {
    inboxId: 99,
    pubsubToken: 'token-1',
    accountId: 7,
    userId: 42,
  };

  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('reuses one subscription for multiple listeners on the same inbox', () => {
    const firstListener = vi.fn();
    const secondListener = vi.fn();
    const releaseFirst = acquireEvolutionConnectionCable({
      ...context,
      onUpdate: firstListener,
    });
    const releaseSecond = acquireEvolutionConnectionCable({
      ...context,
      onUpdate: secondListener,
    });

    expect(createConsumer).toHaveBeenCalledTimes(1);
    expect(subscriptions.create).toHaveBeenCalledTimes(1);

    const { received } = subscriptions.create.mock.calls[0][1];
    received({
      connection_status: 'connecting',
      qrcode_base64: 'data:image/png;base64,abc',
    });

    expect(firstListener).toHaveBeenCalled();
    expect(secondListener).toHaveBeenCalled();

    releaseFirst();
    expect(mockUnsubscribe).not.toHaveBeenCalled();

    releaseSecond();
    expect(mockUnsubscribe).toHaveBeenCalledTimes(1);
  });

  it('exposes disconnect alert helper', () => {
    expect(typeof onEvolutionConnectionClosed).toBe('function');
  });
});
