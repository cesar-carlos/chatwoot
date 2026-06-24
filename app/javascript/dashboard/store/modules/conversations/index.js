import types from '../../mutation-types';
import getters, { getSelectedChatConversation } from './getters';
import actions from './actions';
import {
  findPendingMessageIndex,
  messageCreatedAt,
  normalizeStoreMessage,
} from './helpers';
import { MESSAGE_STATUS } from 'shared/constants/messages';
import {
  isNonActivityMessage,
  mergeConversationOnListRefresh,
  messageCreatedAtTimestamp,
} from '../../../helper/conversationHelper';
import wootConstants from 'dashboard/constants/globals';
import { BUS_EVENTS } from '../../../../shared/constants/busEvents';
import { emitter } from 'shared/helpers/mitt';
import { CONTENT_TYPES } from 'dashboard/components-next/message/constants.js';
import { MAX_SEARCH_INJECTED_MESSAGES } from '../../../composables/fork/conversationSearchInjectedMessages';

const state = {
  allConversations: [],
  attachments: {},
  listLoadingStatus: true,
  chatStatusFilter: wootConstants.STATUS_TYPE.OPEN,
  chatSortFilter: wootConstants.SORT_BY_TYPE.LATEST,
  currentInbox: null,
  selectedChatId: null,
  appliedFilters: [],
  contextMenuChatId: null,
  conversationParticipants: [],
  conversationLastSeen: null,
  syncConversationsMessages: {},
  conversationFilters: {},
  copilotAssistant: {},
  // FORK: in-conversation message search — IDs inserted via search jump (per conversation)
  searchInjectedByConversationId: {},
};

const getConversationById = _state => conversationId => {
  return _state.allConversations.find(c => c.id === conversationId);
};

// mutations
export const mutations = {
  [types.SET_ALL_CONVERSATION](_state, conversationList) {
    const newAllConversations = [..._state.allConversations];
    conversationList.forEach(conversation => {
      const indexInCurrentList = newAllConversations.findIndex(
        c => c.id === conversation.id
      );
      if (indexInCurrentList < 0) {
        newAllConversations.push(conversation);
      } else if (conversation.id !== _state.selectedChatId) {
        // If the conversation is already in the list, replace it
        // Added this to fix the issue of the conversation not being updated
        // When reconnecting to the websocket. If the selectedChatId is not the same as
        // the conversation.id in the store, replace the existing conversation with the new one
        // FORK: preserve websocket message preview data during list refresh
        newAllConversations[indexInCurrentList] =
          mergeConversationOnListRefresh(
            newAllConversations[indexInCurrentList],
            conversation
          );
      } else {
        // If the conversation is already in the list and selectedChatId is the same,
        // replace all data except the messages array, attachments, dataFetched, allMessagesLoaded
        const existingConversation = newAllConversations[indexInCurrentList];
        newAllConversations[indexInCurrentList] = {
          ...conversation,
          allMessagesLoaded: existingConversation.allMessagesLoaded,
          messages: existingConversation.messages,
          dataFetched: existingConversation.dataFetched,
        };
      }
    });
    _state.allConversations = newAllConversations;
  },
  [types.EMPTY_ALL_CONVERSATION](_state) {
    _state.allConversations = [];
    _state.selectedChatId = null;
  },
  [types.SET_ALL_MESSAGES_LOADED](_state, conversationId) {
    const chat = getConversationById(_state)(conversationId);
    if (chat) {
      chat.allMessagesLoaded = true;
    }
  },

  [types.CLEAR_ALL_MESSAGES_LOADED](_state, conversationId) {
    const chat = getConversationById(_state)(conversationId);
    if (chat) {
      chat.allMessagesLoaded = false;
    }
  },
  [types.CLEAR_CURRENT_CHAT_WINDOW](_state) {
    if (_state.selectedChatId && _state.searchInjectedByConversationId) {
      delete _state.searchInjectedByConversationId[_state.selectedChatId];
    }
    _state.selectedChatId = null;
  },

  [types.SET_PREVIOUS_CONVERSATIONS](_state, { id, data }) {
    if (data.length) {
      const [chat] = _state.allConversations.filter(c => c.id === id);
      chat.messages.unshift(...data);
    }
  },
  [types.SET_ALL_ATTACHMENTS](_state, { id, data }) {
    _state.attachments[id] = [...data];
  },
  [types.SET_MISSING_MESSAGES](_state, { id, data }) {
    const [chat] = _state.allConversations.filter(c => c.id === id);
    if (!chat) return;
    chat.messages = data;
  },
  [types.INSERT_MESSAGES_AROUND](_state, { id, data }) {
    const chat = getConversationById(_state)(id);
    if (!chat) return;

    const messageMap = new Map(
      (chat.messages || []).map(message => [message.id, message])
    );
    data.forEach(message => {
      messageMap.set(message.id, normalizeStoreMessage(message));
    });
    chat.messages = Array.from(messageMap.values()).sort(
      (left, right) => messageCreatedAt(left) - messageCreatedAt(right)
    );
  },

  // FORK: in-conversation message search — registry and prune for injected messages
  [types.REGISTER_SEARCH_INJECTED](_state, { id, messageIds }) {
    if (!messageIds?.length) return;

    const registry = _state.searchInjectedByConversationId[id] || [];
    const seen = new Set(registry);
    const next = [...registry];

    messageIds.forEach(messageId => {
      if (seen.has(messageId)) return;
      seen.add(messageId);
      next.push(messageId);
    });

    _state.searchInjectedByConversationId[id] = next;
  },

  [types.DEREGISTER_SEARCH_INJECTED](_state, { id, messageIds }) {
    if (!messageIds?.length) return;

    const registry = _state.searchInjectedByConversationId[id];
    if (!registry?.length) return;

    const remove = new Set(messageIds);
    _state.searchInjectedByConversationId[id] = registry.filter(
      messageId => !remove.has(messageId)
    );
  },

  [types.CLEAR_SEARCH_INJECTED](_state, conversationId) {
    if (conversationId) {
      delete _state.searchInjectedByConversationId[conversationId];
      return;
    }

    _state.searchInjectedByConversationId = {};
  },

  [types.PRUNE_SEARCH_INJECTED](_state, { id, protectedIds = [] }) {
    const chat = getConversationById(_state)(id);
    const registry = _state.searchInjectedByConversationId[id];
    if (!chat || !registry?.length || registry.length <= MAX_SEARCH_INJECTED_MESSAGES) {
      return;
    }

    const protectedSet = new Set(protectedIds);
    const toRemove = [];

    registry.forEach(messageId => {
      if (registry.length - toRemove.length <= MAX_SEARCH_INJECTED_MESSAGES) return;
      if (protectedSet.has(messageId)) return;

      toRemove.push(messageId);
    });

    if (!toRemove.length) return;

    const removeSet = new Set(toRemove);
    chat.messages = (chat.messages || []).filter(
      message => !removeSet.has(message.id)
    );
    _state.searchInjectedByConversationId[id] = registry.filter(
      messageId => !removeSet.has(messageId)
    );
  },

  [types.SET_CHAT_DATA_FETCHED](_state, conversationId) {
    const chat = getConversationById(_state)(conversationId);
    if (chat) {
      chat.dataFetched = true;
    }
  },

  [types.SET_CURRENT_CHAT_WINDOW](_state, activeChat) {
    if (activeChat) {
      _state.selectedChatId = activeChat.id;
    }
  },

  [types.ASSIGN_AGENT](_state, { conversationId, assignee }) {
    const chat = getConversationById(_state)(conversationId);
    if (chat) {
      chat.meta.assignee = assignee;
    }
  },

  [types.ASSIGN_TEAM](_state, { team, conversationId }) {
    const [chat] = _state.allConversations.filter(c => c.id === conversationId);
    chat.meta.team = team;
  },

  [types.UPDATE_CONVERSATION_LAST_ACTIVITY](
    _state,
    { lastActivityAt, conversationId }
  ) {
    const [chat] = _state.allConversations.filter(c => c.id === conversationId);
    if (chat) {
      chat.last_activity_at = lastActivityAt;
    }
  },
  [types.ASSIGN_PRIORITY](_state, { priority, conversationId }) {
    const [chat] = _state.allConversations.filter(c => c.id === conversationId);
    chat.priority = priority;
  },

  [types.UPDATE_CONVERSATION_CUSTOM_ATTRIBUTES](
    _state,
    { conversationId, customAttributes }
  ) {
    const conversation = _state.allConversations.find(
      c => c.id === conversationId
    );
    if (conversation) {
      conversation.custom_attributes = {
        ...conversation.custom_attributes,
        ...customAttributes,
      };
    }
  },

  [types.CHANGE_CONVERSATION_STATUS](
    _state,
    { conversationId, status, snoozedUntil }
  ) {
    const conversation =
      getters.getConversationById(_state)(conversationId) || {};
    conversation.snoozed_until = snoozedUntil;
    conversation.status = status;
  },

  [types.MUTE_CONVERSATION](_state) {
    const [chat] = getSelectedChatConversation(_state);
    chat.muted = true;
  },

  [types.UNMUTE_CONVERSATION](_state) {
    const [chat] = getSelectedChatConversation(_state);
    chat.muted = false;
  },

  [types.ADD_CONVERSATION_ATTACHMENTS](_state, message) {
    // early return if the message has not been sent, or has no attachments
    if (
      message.status !== MESSAGE_STATUS.SENT ||
      !message.attachments?.length
    ) {
      return;
    }

    const id = message.conversation_id;
    const existingAttachments = _state.attachments[id] || [];

    const attachmentsToAdd = message.attachments.filter(attachment => {
      // if the attachment is not already in the store, add it
      // this is to prevent duplicates
      return !existingAttachments.some(
        existingAttachment => existingAttachment.id === attachment.id
      );
    });

    // replace the attachments in the store
    _state.attachments[id] = [...existingAttachments, ...attachmentsToAdd];
  },

  [types.DELETE_CONVERSATION_ATTACHMENTS](_state, message) {
    if (message.status !== MESSAGE_STATUS.SENT) return;

    const { conversation_id: id } = message;
    const existingAttachments = _state.attachments[id] || [];
    if (!existingAttachments.length) return;

    _state.attachments[id] = existingAttachments.filter(attachment => {
      return attachment.message_id !== message.id;
    });
  },

  [types.ADD_MESSAGE]({ allConversations, selectedChatId }, message) {
    const { conversation_id: conversationId } = message;
    const [chat] = getSelectedChatConversation({
      allConversations,
      selectedChatId: conversationId,
    });
    if (!chat) return;

    const pendingMessageIndex = findPendingMessageIndex(chat, message);
    if (pendingMessageIndex !== -1) {
      chat.messages[pendingMessageIndex] = message;
    } else {
      chat.messages.push(message);
      chat.timestamp = message.created_at;
      const { conversation: { unread_count: unreadCount = 0 } = {} } = message;
      chat.unread_count = unreadCount;
      // FORK: keep conversation list preview in sync with websocket messages
      if (isNonActivityMessage(message)) {
        const existingPreview = chat.last_non_activity_message;
        if (
          !existingPreview ||
          messageCreatedAtTimestamp(message) >=
            messageCreatedAtTimestamp(existingPreview)
        ) {
          chat.last_non_activity_message = message;
        }
      }
      if (selectedChatId === conversationId) {
        emitter.emit(BUS_EVENTS.SCROLL_TO_MESSAGE);
      }
    }
  },

  [types.ADD_CONVERSATION](_state, conversation) {
    const exists = _state.allConversations.some(c => c.id === conversation.id);
    if (!exists) {
      _state.allConversations.push(conversation);
    }
  },

  [types.DELETE_CONVERSATION](_state, conversationId) {
    _state.allConversations = _state.allConversations.filter(
      c => c.id !== conversationId
    );
  },

  [types.UPDATE_CONVERSATION](_state, conversation) {
    const { allConversations } = _state;
    const index = allConversations.findIndex(c => c.id === conversation.id);

    if (index > -1) {
      const selectedConversation = allConversations[index];

      // ignore out of order events
      if (conversation.updated_at < selectedConversation.updated_at) {
        return;
      }

      const { messages, ...updates } = conversation;
      allConversations[index] = { ...selectedConversation, ...updates };
      if (_state.selectedChatId === conversation.id) {
        emitter.emit(BUS_EVENTS.SCROLL_TO_MESSAGE);
      }
    } else {
      const { conversationType } = _state.conversationFilters || {};
      const { MENTION, PARTICIPATING } = wootConstants.CONVERSATION_TYPE;
      if (![MENTION, PARTICIPATING].includes(conversationType)) {
        _state.allConversations.push(conversation);
      }
    }
  },

  [types.SET_LIST_LOADING_STATUS](_state) {
    _state.listLoadingStatus = true;
  },

  [types.CLEAR_LIST_LOADING_STATUS](_state) {
    _state.listLoadingStatus = false;
  },

  [types.UPDATE_MESSAGE_UNREAD_COUNT](
    _state,
    { id, lastSeen, unreadCount = 0 }
  ) {
    const [chat] = _state.allConversations.filter(c => c.id === id);
    if (chat) {
      chat.agent_last_seen_at = lastSeen;
      chat.unread_count = unreadCount;
    }
  },
  [types.CHANGE_CHAT_STATUS_FILTER](_state, data) {
    _state.chatStatusFilter = data;
  },

  [types.CHANGE_CHAT_SORT_FILTER](_state, data) {
    _state.chatSortFilter = data;
  },

  // Update assignee on action cable message
  [types.UPDATE_ASSIGNEE](_state, payload) {
    const chat = getConversationById(_state)(payload.id);
    if (chat) {
      chat.meta.assignee = payload.assignee;
    }
  },

  [types.UPDATE_CONVERSATION_CONTACT](_state, { conversationId, ...payload }) {
    const [chat] = _state.allConversations.filter(c => c.id === conversationId);
    if (chat) {
      chat.meta.sender = payload;
    }
  },

  [types.UPDATE_MESSAGE_CALL_STATUS](
    _state,
    { conversationId, callStatus, callSid }
  ) {
    const chat = getConversationById(_state)(conversationId);
    if (!chat) return;

    const message = (chat.messages || []).find(
      m =>
        m.content_type === CONTENT_TYPES.VOICE_CALL &&
        m.call?.provider_call_id === callSid
    );
    if (!message?.call) return;

    message.call = { ...message.call, status: callStatus };
  },

  [types.SET_ACTIVE_INBOX](_state, inboxId) {
    _state.currentInbox = inboxId ? parseInt(inboxId, 10) : null;
  },

  [types.SET_CONVERSATION_CAN_REPLY](_state, { conversationId, canReply }) {
    const [chat] = _state.allConversations.filter(c => c.id === conversationId);
    if (chat) {
      chat.can_reply = canReply;
    }
  },

  [types.CLEAR_CONTACT_CONVERSATIONS](_state, contactId) {
    const chats = _state.allConversations.filter(
      c => c.meta.sender.id !== contactId
    );
    _state.allConversations = chats;
  },

  [types.SET_CONVERSATION_FILTERS](_state, data) {
    _state.appliedFilters = data;
  },

  [types.CLEAR_CONVERSATION_FILTERS](_state) {
    _state.appliedFilters = [];
  },

  [types.SET_LAST_MESSAGE_ID_IN_SYNC_CONVERSATION](
    _state,
    { conversationId, messageId }
  ) {
    _state.syncConversationsMessages[conversationId] = messageId;
  },

  [types.SET_CONTEXT_MENU_CHAT_ID](_state, chatId) {
    _state.contextMenuChatId = chatId;
  },

  [types.SET_CHAT_LIST_FILTERS](_state, data) {
    _state.conversationFilters = data;
  },
  [types.UPDATE_CHAT_LIST_FILTERS](_state, data) {
    _state.conversationFilters = { ..._state.conversationFilters, ...data };
  },
  [types.SET_INBOX_CAPTAIN_ASSISTANT](_state, data) {
    _state.copilotAssistant = data.assistant;
  },
};

export default {
  state,
  getters,
  actions,
  mutations,
};
