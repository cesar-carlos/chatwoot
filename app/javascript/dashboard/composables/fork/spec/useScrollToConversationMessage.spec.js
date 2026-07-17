import { ref } from 'vue';
import { useScrollToConversationMessage } from '../useScrollToConversationMessage';
import types from 'dashboard/store/mutation-types';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import MessageApi from 'dashboard/api/inbox/message';
import { useAlert } from 'dashboard/composables';

const commit = vi.fn();
const getSelectedChat = vi.fn();

vi.mock('vuex', () => ({
  useStore: () => ({
    commit,
    getters: {
      get getSelectedChat() {
        return getSelectedChat();
      },
    },
  }),
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

vi.mock('dashboard/composables', () => ({
  useAlert: vi.fn(),
}));

vi.mock(
  'dashboard/composables/fork/conversationSearchInjectedMessages',
  () => ({
    collectVisibleMessageIds: vi.fn(() => []),
    newMessageIds: vi.fn((existing, incoming) =>
      incoming
        .map(message => message.id)
        .filter(id => !(existing || []).some(message => message.id === id))
    ),
  })
);

describe('useScrollToConversationMessage', () => {
  beforeEach(() => {
    commit.mockReset();
    getSelectedChat.mockReset();
    MessageApi.getPreviousMessages = vi.fn();
    vi.spyOn(emitter, 'emit').mockImplementation(() => {});
    window.matchMedia = vi.fn().mockReturnValue({ matches: false });
    document.body.innerHTML = '';
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  it('emits scroll when the message element already exists', async () => {
    const message = document.createElement('div');
    message.id = 'message42';
    document.body.appendChild(message);

    const { scrollToMessage } = useScrollToConversationMessage({
      conversationId: ref(7),
      onClose: vi.fn(),
    });

    const result = await scrollToMessage({ id: 42, content: 'hello' });

    expect(result).toBe(true);
    expect(emitter.emit).toHaveBeenCalledWith(BUS_EVENTS.SCROLL_TO_MESSAGE, {
      messageId: 42,
    });
    expect(commit).not.toHaveBeenCalled();
  });

  it('merges missing messages and registers injected ids before scrolling', async () => {
    getSelectedChat.mockReturnValue({ id: 7, messages: [{ id: 1 }] });
    const target = { id: 42, content: 'hello', created_at: 1_700_000_000 };

    let lookups = 0;
    const messageElement = document.createElement('div');
    messageElement.id = 'message42';
    const originalGetElementById = document.getElementById.bind(document);
    vi.spyOn(document, 'getElementById').mockImplementation(id => {
      if (id === 'message42') {
        lookups += 1;
        return lookups >= 2 ? messageElement : null;
      }
      return originalGetElementById(id);
    });

    const { scrollToMessage } = useScrollToConversationMessage({
      conversationId: ref(7),
      onClose: vi.fn(),
    });

    const result = await scrollToMessage(target);

    expect(result).toBe(true);
    expect(MessageApi.getPreviousMessages).not.toHaveBeenCalled();
    expect(commit).toHaveBeenCalledWith(types.INSERT_MESSAGES_AROUND, {
      id: 7,
      data: [target],
    });
    expect(commit).toHaveBeenCalledWith(types.REGISTER_SEARCH_INJECTED, {
      id: 7,
      messageIds: [42],
    });
    expect(emitter.emit).toHaveBeenCalledWith(BUS_EVENTS.SCROLL_TO_MESSAGE, {
      messageId: 42,
    });
  });

  it('shows an alert when the message cannot be located', async () => {
    getSelectedChat.mockReturnValue({ id: 7, messages: [] });
    MessageApi.getPreviousMessages = vi
      .fn()
      .mockResolvedValue({ data: { payload: [] } });

    const { scrollToMessage } = useScrollToConversationMessage({
      conversationId: ref(7),
      onClose: vi.fn(),
    });

    const result = await scrollToMessage({ id: 99, content: 'missing' });

    expect(result).toBe(false);
    expect(useAlert).toHaveBeenCalledWith(
      'CONVERSATION.MESSAGE_SEARCH.MESSAGE_NOT_FOUND'
    );
    expect(emitter.emit).not.toHaveBeenCalled();
  });

  it('loads messages with tight window first then scrolls', async () => {
    vi.useFakeTimers();
    getSelectedChat.mockReturnValue({ id: 7, messages: [] });
    const targetOnly = [{ id: 42, content: 'target', created_at: 2 }];
    MessageApi.getPreviousMessages = vi.fn().mockResolvedValue({
      data: { payload: targetOnly },
    });

    let lookups = 0;
    const messageElement = document.createElement('div');
    messageElement.id = 'message42';
    vi.spyOn(document, 'getElementById').mockImplementation(id => {
      if (id === 'message42') {
        lookups += 1;
        return lookups >= 2 ? messageElement : null;
      }
      return null;
    });

    const { scrollToMessage } = useScrollToConversationMessage({
      conversationId: ref(7),
    });

    const result = await scrollToMessage({ id: 42 });

    expect(result).toBe(true);
    expect(MessageApi.getPreviousMessages).toHaveBeenCalledTimes(1);
    expect(MessageApi.getPreviousMessages).toHaveBeenCalledWith({
      conversationId: 7,
      after: 42,
      before: 43,
    });
    expect(commit).toHaveBeenCalledWith(types.INSERT_MESSAGES_AROUND, {
      id: 7,
      data: targetOnly,
    });
    expect(emitter.emit).toHaveBeenCalledWith(BUS_EVENTS.SCROLL_TO_MESSAGE, {
      messageId: 42,
    });

    vi.advanceTimersByTime(400);
    expect(messageElement.classList.contains('message-locate-pulse')).toBe(
      true
    );
    vi.useRealTimers();
  });

  it('falls back to wide window when tight fetch misses the target', async () => {
    getSelectedChat.mockReturnValue({ id: 7, messages: [] });
    const wide = [
      { id: 41, content: 'before', created_at: 1 },
      { id: 42, content: 'target', created_at: 2 },
    ];
    MessageApi.getPreviousMessages = vi
      .fn()
      .mockResolvedValueOnce({ data: { payload: [] } })
      .mockResolvedValueOnce({ data: { payload: wide } });

    let lookups = 0;
    const messageElement = document.createElement('div');
    messageElement.id = 'message42';
    vi.spyOn(document, 'getElementById').mockImplementation(id => {
      if (id === 'message42') {
        lookups += 1;
        return lookups >= 2 ? messageElement : null;
      }
      return null;
    });

    const { scrollToMessage } = useScrollToConversationMessage({
      conversationId: ref(7),
    });

    const result = await scrollToMessage({ id: 42 });

    expect(result).toBe(true);
    expect(MessageApi.getPreviousMessages).toHaveBeenNthCalledWith(1, {
      conversationId: 7,
      after: 42,
      before: 43,
    });
    expect(MessageApi.getPreviousMessages).toHaveBeenNthCalledWith(2, {
      conversationId: 7,
      before: 142,
      after: 0,
    });
    expect(commit).toHaveBeenCalledWith(types.INSERT_MESSAGES_AROUND, {
      id: 7,
      data: wide,
    });
  });
});
