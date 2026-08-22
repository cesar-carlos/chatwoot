import { inject, provide, ref } from 'vue';
import {
  MAX_FORWARD_MESSAGES,
  messageCanBeForwarded,
} from 'customDashboard/composables/useMessageForward';

export const MessageForwardSelectionKey = Symbol('MessageForwardSelection');

export function isForwardableTimelineMessage(message) {
  if (!message) return false;

  const status = message.status;
  const isFailedOrProcessing = status === 'failed' || status === 'progress';
  const attrs = message.content_attributes || message.contentAttributes || {};
  const deleted = Boolean(attrs.deleted);
  const isPrivate = Boolean(message.private);

  return (
    messageCanBeForwarded(message) &&
    !isFailedOrProcessing &&
    !deleted &&
    !isPrivate
  );
}

export function createMessageForwardSelection({
  onOpenForward,
  onMaxReached,
} = {}) {
  const isSelecting = ref(false);
  const selected = ref([]);
  const timeline = ref([]);
  const anchorId = ref(null);

  function isSelected(id) {
    return selected.value.some(item => Number(item.id) === Number(id));
  }

  function setTimeline(messages) {
    timeline.value = Array.isArray(messages) ? messages : [];
  }

  function enterWith(message) {
    if (!isForwardableTimelineMessage(message)) return;
    isSelecting.value = true;
    selected.value = [message];
    anchorId.value = message.id;
  }

  function addMessages(messages) {
    const next = new Map(
      selected.value.map(item => [Number(item.id), item])
    );
    let hitMax = false;

    messages.forEach(message => {
      if (!isForwardableTimelineMessage(message)) return;
      const id = Number(message.id);
      if (next.has(id)) return;
      if (next.size >= MAX_FORWARD_MESSAGES) {
        hitMax = true;
        return;
      }
      next.set(id, message);
    });

    selected.value = [...next.values()];
    if (hitMax) onMaxReached?.();
  }

  function selectRange(target) {
    const ordered = timeline.value.filter(isForwardableTimelineMessage);
    const anchorIndex = ordered.findIndex(
      item => Number(item.id) === Number(anchorId.value)
    );
    const targetIndex = ordered.findIndex(
      item => Number(item.id) === Number(target.id)
    );
    if (anchorIndex < 0 || targetIndex < 0) {
      addMessages([target]);
      return;
    }

    const from = Math.min(anchorIndex, targetIndex);
    const to = Math.max(anchorIndex, targetIndex);
    addMessages(ordered.slice(from, to + 1));
  }

  function toggle(message, { shiftKey } = {}) {
    if (!isForwardableTimelineMessage(message)) return;

    if (!isSelecting.value) {
      enterWith(message);
      return;
    }

    if (shiftKey && anchorId.value != null) {
      selectRange(message);
      return;
    }

    if (isSelected(message.id)) {
      selected.value = selected.value.filter(
        item => Number(item.id) !== Number(message.id)
      );
      anchorId.value = message.id;
      return;
    }

    addMessages([message]);
    anchorId.value = message.id;
  }

  function exit() {
    isSelecting.value = false;
    selected.value = [];
    anchorId.value = null;
  }

  function openForward(messages) {
    const list = messages?.length ? messages : selected.value;
    if (!list.length) return;
    onOpenForward?.(list);
  }

  return {
    isSelecting,
    selected,
    isSelected,
    setTimeline,
    enterWith,
    toggle,
    exit,
    openForward,
    canSelect: isForwardableTimelineMessage,
    max: MAX_FORWARD_MESSAGES,
  };
}

export function provideMessageForwardSelection(api) {
  provide(MessageForwardSelectionKey, api);
  return api;
}

export function useMessageForwardSelection() {
  return inject(MessageForwardSelectionKey, null);
}
