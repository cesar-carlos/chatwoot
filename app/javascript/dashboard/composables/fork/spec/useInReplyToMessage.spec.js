import { ref } from 'vue';
import { useInReplyToMessage } from '../useInReplyToMessage';
import MessageApi from 'dashboard/api/inbox/message';
import { useCamelCase } from 'dashboard/composables/useTransformKeys';

vi.mock('dashboard/composables/useTransformKeys', () => ({
  useCamelCase: vi.fn(message => message),
}));

describe('useInReplyToMessage', () => {
  beforeEach(() => {
    MessageApi.getPreviousMessages = vi.fn();
    useCamelCase.mockImplementation(message => message);
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  it('returns the parent from the current message list', () => {
    const parent = { id: 10, content: 'hello' };
    const messages = ref([parent]);
    const currentChat = ref({ id: 1, messages: [] });
    const { getInReplyToMessage } = useInReplyToMessage({
      messages,
      currentChat,
    });

    expect(
      getInReplyToMessage({
        contentAttributes: { inReplyTo: 10 },
      })
    ).toEqual(parent);
  });

  it('returns a loading stub and fetches when parent is missing', async () => {
    const messages = ref([]);
    const currentChat = ref({ id: 7, messages: [] });
    MessageApi.getPreviousMessages = vi.fn().mockResolvedValue({
      data: { payload: [{ id: 99, content: 'loaded' }] },
    });

    const { getInReplyToMessage, fetchedReplyMessages } = useInReplyToMessage({
      messages,
      currentChat,
    });

    const stub = getInReplyToMessage({
      content_attributes: { in_reply_to: 99 },
    });

    expect(stub).toEqual({ id: 99, replyPreviewState: 'loading' });
    expect(MessageApi.getPreviousMessages).toHaveBeenCalledWith({
      conversationId: 7,
      after: 99,
      before: 100,
    });

    await vi.waitFor(() => {
      expect(fetchedReplyMessages.get(99)?.content).toBe('loaded');
    });
  });

  it('returns missing stub when fetch finds nothing', async () => {
    const messages = ref([]);
    const currentChat = ref({ id: 7, messages: [] });
    MessageApi.getPreviousMessages = vi
      .fn()
      .mockResolvedValue({ data: { payload: [] } });

    const { getInReplyToMessage, fetchedReplyMessages } = useInReplyToMessage({
      messages,
      currentChat,
    });

    getInReplyToMessage({ contentAttributes: { in_reply_to: 5 } });

    await vi.waitFor(() => {
      expect(fetchedReplyMessages.get(5)).toBeNull();
    });

    expect(
      getInReplyToMessage({ contentAttributes: { in_reply_to: 5 } })
    ).toEqual({ id: 5, replyPreviewState: 'missing' });
  });
});
