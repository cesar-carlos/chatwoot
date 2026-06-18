import { effectScope, nextTick, reactive } from 'vue';
import { useStore } from 'vuex';
import { useBulkActions } from '../chatlist/useBulkActions';
import { useMapGetter } from 'dashboard/composables/store.js';
import { useAlert } from 'dashboard/composables';
import { useConversationRequiredAttributes } from 'dashboard/composables/useConversationRequiredAttributes';

vi.mock('vuex', () => ({
  useStore: vi.fn(),
}));
vi.mock('dashboard/composables/store.js', () => ({
  useMapGetter: vi.fn(),
}));
vi.mock('dashboard/composables', () => ({
  useAlert: vi.fn(),
}));
vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));
vi.mock('dashboard/composables/useConversationRequiredAttributes', () => ({
  useConversationRequiredAttributes: vi.fn(() => ({
    checkMissingAttributes: vi.fn(() => ({ hasMissing: false })),
  })),
}));

describe('useBulkActions onAssignAgent', () => {
  let store;
  let conversations;
  let scope;

  const agent = { id: 5, name: 'Agent Smith' };

  const createBulkActions = () => {
    scope?.stop();
    scope = effectScope(true);
    return scope.run(() => useBulkActions());
  };

  const buildHttpError = status => {
    const error = new Error(`HTTP ${status}`);
    error.response = { status };
    return error;
  };

  beforeEach(() => {
    conversations = {
      42: { id: 42, meta: { assignee: null } },
    };

    const conversationState = reactive({
      allConversations: Object.values(conversations),
    });

    store = {
      dispatch: vi.fn().mockResolvedValue(undefined),
      getters: {
        getConversationById: id => conversations[id],
      },
      state: {
        conversations: conversationState,
      },
    };

    useStore.mockReturnValue(store);
    useMapGetter.mockImplementation(getter => {
      if (getter === 'bulkActions/getSelectedConversationIds') {
        return { value: [] };
      }

      return { value: undefined };
    });
    useConversationRequiredAttributes.mockReturnValue({
      checkMissingAttributes: vi.fn(() => ({ hasMissing: false })),
    });
    useAlert.mockClear();
  });

  afterEach(() => {
    scope?.stop();
  });

  it('assigns a single conversation and keeps pending until assignee updates', async () => {
    const { onAssignAgent, isAssignPending } = createBulkActions();

    await onAssignAgent(agent, 42);

    expect(store.dispatch).toHaveBeenCalledWith('bulkActions/process', {
      type: 'Conversation',
      ids: [42],
      fields: { assignee_id: 5 },
    });
    expect(isAssignPending(42)).toBe(true);

    conversations[42] = { id: 42, meta: { assignee: { id: 5 } } };
    store.state.conversations.allConversations = Object.values(conversations);
    await nextTick();

    expect(isAssignPending(42)).toBe(false);
    expect(useAlert).toHaveBeenCalledWith(
      'CONVERSATION.CARD_CONTEXT_MENU.API.AGENT_ASSIGNMENT.SUCCESFUL'
    );
  });

  it('maps 403 errors to permission denied alert and clears pending', async () => {
    store.dispatch.mockRejectedValueOnce(buildHttpError(403));

    const { onAssignAgent, isAssignPending } = createBulkActions();

    await onAssignAgent(agent, 42);

    expect(useAlert).toHaveBeenCalledWith(
      'CONVERSATION.CARD_CONTEXT_MENU.API.AGENT_ASSIGNMENT.PERMISSION_DENIED'
    );
    expect(isAssignPending(42)).toBe(false);
  });

  it('maps 422 errors to validation failed alert', async () => {
    store.dispatch.mockRejectedValueOnce(buildHttpError(422));

    const { onAssignAgent } = createBulkActions();

    await onAssignAgent(agent, 42);

    expect(useAlert).toHaveBeenCalledWith(
      'CONVERSATION.CARD_CONTEXT_MENU.API.AGENT_ASSIGNMENT.VALIDATION_FAILED'
    );
  });

  it('maps timeout errors to timeout alert', async () => {
    store.dispatch.mockRejectedValueOnce(buildHttpError(504));

    const { onAssignAgent } = createBulkActions();

    await onAssignAgent(agent, 42);

    expect(useAlert).toHaveBeenCalledWith(
      'CONVERSATION.CARD_CONTEXT_MENU.API.AGENT_ASSIGNMENT.TIMEOUT'
    );
  });

  it('maps generic failures to failed alert', async () => {
    store.dispatch.mockRejectedValueOnce(new Error('network'));

    const { onAssignAgent } = createBulkActions();

    await onAssignAgent(agent, 42);

    expect(useAlert).toHaveBeenCalledWith(
      'CONVERSATION.CARD_CONTEXT_MENU.API.AGENT_ASSIGNMENT.FAILED'
    );
  });

  it('ignores duplicate assign requests while pending', async () => {
    let resolveDispatch;
    store.dispatch.mockImplementation(
      () =>
        new Promise(resolve => {
          resolveDispatch = resolve;
        })
    );

    const { onAssignAgent } = createBulkActions();

    const firstRequest = onAssignAgent(agent, 42);
    await onAssignAgent(agent, 42);

    expect(store.dispatch).toHaveBeenCalledTimes(1);
    expect(useAlert).toHaveBeenCalledWith(
      'CONVERSATION.CARD_CONTEXT_MENU.API.AGENT_ASSIGNMENT.PENDING'
    );

    resolveDispatch();
    await firstRequest;
  });
});
