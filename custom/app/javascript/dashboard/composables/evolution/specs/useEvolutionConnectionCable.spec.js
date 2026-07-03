import { beforeEach, describe, expect, it, vi } from 'vitest';
import { effectScope, nextTick, ref } from 'vue';

const releaseMock = vi.fn();
const acquireEvolutionConnectionCable = vi.fn(() => releaseMock);

vi.mock('customDashboard/lib/evolution/evolutionCableRegistry', () => ({
  acquireEvolutionConnectionCable: (...args) =>
    acquireEvolutionConnectionCable(...args),
}));

vi.mock('dashboard/composables/store', () => ({
  useMapGetter: key => {
    const getters = {
      getCurrentUser: ref({ pubsub_token: 'token-1' }),
      getCurrentAccountId: ref(7),
      getCurrentUserID: ref(42),
    };
    return getters[key];
  },
}));

import { useEvolutionConnectionCable } from 'customDashboard/composables/evolution/useEvolutionConnectionCable';

describe('useEvolutionConnectionCable', () => {
  let scope;

  beforeEach(() => {
    vi.clearAllMocks();
    scope?.stop();
  });

  it('acquires a deduped cable subscription for the inbox id', async () => {
    scope = effectScope(true);
    const inboxId = ref(99);
    const onUpdate = vi.fn();

    scope.run(() => {
      useEvolutionConnectionCable(inboxId, onUpdate);
    });
    await nextTick();

    expect(acquireEvolutionConnectionCable).toHaveBeenCalledWith({
      inboxId: 99,
      pubsubToken: 'token-1',
      accountId: 7,
      userId: 42,
      onUpdate,
    });
  });

  it('releases the cable subscription when unsubscribe is called', async () => {
    scope = effectScope(true);
    const inboxId = ref(99);
    let unsubscribe;

    scope.run(() => {
      ({ unsubscribe } = useEvolutionConnectionCable(inboxId, vi.fn()));
    });
    await nextTick();

    unsubscribe();
    expect(releaseMock).toHaveBeenCalled();
  });
});
