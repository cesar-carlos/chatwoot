import { nextTick, reactive } from 'vue';
import {
  normalizeAssignConversationIds,
  useAssignMePending,
} from '../useAssignMePending';

describe('normalizeAssignConversationIds', () => {
  it('returns selected conversation ids when conversationId is null', () => {
    expect(normalizeAssignConversationIds(null, [1, 2])).toEqual([1, 2]);
  });

  it('wraps a single conversation id in an array', () => {
    expect(normalizeAssignConversationIds(42, [1, 2])).toEqual([42]);
  });

  it('returns the array when conversationId is already an array', () => {
    expect(normalizeAssignConversationIds([7, 8], [1, 2])).toEqual([7, 8]);
  });
});

describe('useAssignMePending', () => {
  it('tracks pending conversation ids', () => {
    const { isAssignPending, markAssignPending, clearAssignPending } =
      useAssignMePending();

    markAssignPending([10, 11]);
    expect(isAssignPending(10)).toBe(true);
    expect(isAssignPending(11)).toBe(true);
    expect(isAssignPending(12)).toBe(false);

    clearAssignPending([10]);
    expect(isAssignPending(10)).toBe(false);
    expect(isAssignPending(11)).toBe(true);
  });

  it('prevents duplicate pending ids', () => {
    const { isAssignPending, markAssignPending } = useAssignMePending();

    markAssignPending([5]);
    markAssignPending([5]);

    expect(isAssignPending(5)).toBe(true);
  });

  it('supports concurrent pending conversations', () => {
    const { isAssignPending, markAssignPending, clearAssignPending } =
      useAssignMePending();

    markAssignPending([1]);
    markAssignPending([2]);

    expect(isAssignPending(1)).toBe(true);
    expect(isAssignPending(2)).toBe(true);

    clearAssignPending([1]);
    expect(isAssignPending(1)).toBe(false);
    expect(isAssignPending(2)).toBe(true);
  });

  it('stores expected assignee id with markAssignPendingUntilResolved', () => {
    const {
      isAssignPending,
      markAssignPendingUntilResolved,
      resolveAssignPending,
    } = useAssignMePending();

    markAssignPendingUntilResolved([42], 7);
    expect(isAssignPending(42)).toBe(true);

    resolveAssignPending(42, 6);
    expect(isAssignPending(42)).toBe(true);

    resolveAssignPending(42, 7);
    expect(isAssignPending(42)).toBe(false);
  });

  it('clears pending when store assignee matches expected assignee', async () => {
    const conversations = reactive({
      allConversations: [{ id: 99, meta: { assignee: null } }],
    });
    const store = {
      state: { conversations },
      getters: {
        getConversationById: id =>
          conversations.allConversations.find(item => item.id === id),
      },
    };

    const { isAssignPending, markAssignPendingUntilResolved } =
      useAssignMePending({ store });

    markAssignPendingUntilResolved([99], 5);
    expect(isAssignPending(99)).toBe(true);

    conversations.allConversations = [
      { id: 99, meta: { assignee: { id: 5 } } },
    ];
    await nextTick();

    expect(isAssignPending(99)).toBe(false);
  });
});
