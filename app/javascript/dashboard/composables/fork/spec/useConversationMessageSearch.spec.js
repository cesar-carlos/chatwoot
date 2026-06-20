import { ref, nextTick } from 'vue';
import { useConversationMessageSearch } from '../useConversationMessageSearch';
import ConversationMessageSearchAPI from 'dashboard/api/conversationMessageSearch';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));
vi.mock('dashboard/api/conversationMessageSearch');
vi.mock('dashboard/composables', () => ({
  useTrack: vi.fn(),
}));

describe('useConversationMessageSearch', () => {
  beforeEach(() => {
    vi.useFakeTimers();
    sessionStorage.clear();
    ConversationMessageSearchAPI.search.mockReset();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it('debounces search requests and stores results', async () => {
    ConversationMessageSearchAPI.search.mockResolvedValue({
      data: {
        payload: [{ id: 10, content: 'hello world' }],
        meta: { current_page: 1, has_more: false, search_engine: 'ilike' },
      },
    });

    const conversationId = ref(42);
    const search = useConversationMessageSearch(conversationId);

    search.query.value = 'hello';
    await vi.advanceTimersByTimeAsync(500);
    await nextTick();

    expect(ConversationMessageSearchAPI.search).toHaveBeenCalledWith(
      expect.objectContaining({
        conversationId: 42,
        query: 'hello',
        page: 1,
      })
    );
    expect(search.results.value).toEqual([
      { id: 10, content: 'hello world' },
    ]);
    expect(search.errorMessage.value).toBe('');
  });

  it('clears results for short queries', async () => {
    const conversationId = ref(42);
    const search = useConversationMessageSearch(conversationId);

    search.query.value = 'a';
    await vi.advanceTimersByTimeAsync(500);
    await nextTick();

    expect(ConversationMessageSearchAPI.search).not.toHaveBeenCalled();
    expect(search.results.value).toEqual([]);
  });

  it('surfaces API errors', async () => {
    ConversationMessageSearchAPI.search.mockRejectedValue({
      response: {
        status: 422,
        data: { error: 'Search query must be between 2 and 200 characters' },
      },
    });

    const conversationId = ref(42);
    const search = useConversationMessageSearch(conversationId);

    search.query.value = 'hello';
    await vi.advanceTimersByTimeAsync(500);
    await nextTick();

    expect(search.errorMessage.value).toBe(
      'CONVERSATION.MESSAGE_SEARCH.ERROR_QUERY_LENGTH'
    );
    expect(search.results.value).toEqual([]);
  });
});
