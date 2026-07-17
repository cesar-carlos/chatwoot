<script setup>
import { computed, ref } from 'vue';

import MessageMeta from '../MessageMeta.vue';
// FORK: Evolution Go/Node inbound delete highlight
import Icon from 'next/icon/Icon.vue';

import { useMessageContext } from '../provider.js';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useMapGetter, useStore } from 'dashboard/composables/store';
// FORK: locate quoted parent even when outside the lazy-loaded window
import { useScrollToConversationMessage } from 'dashboard/composables/fork/useScrollToConversationMessage';
// FORK: Evolution Go/Node WhatsApp reactions
import {
  buildReactionChips,
  inboxSupportsReactions,
  messageCanReceiveReaction,
  applyOptimisticReaction,
  sendWhatsappReaction,
  extractReactionErrorMessage,
} from 'customDashboard/composables/useMessageReactions';

import MessageFormatter from 'shared/helpers/MessageFormatter.js';
import { MESSAGE_VARIANTS, ORIENTATION } from '../constants';

const props = defineProps({
  hideMeta: { type: Boolean, default: false },
});

const {
  variant,
  orientation,
  inReplyTo,
  shouldGroupWithNext,
  contentAttributes, // FORK: Evolution Go/Node inbound delete highlight
  content, // FORK: legacy edited prefix detection
  id: messageId,
  conversationId,
  inboxId,
  sourceId,
  status,
  isPrivate,
} = useMessageContext();
const { t } = useI18n();
const store = useStore();
const getInboxById = useMapGetter('inboxes/getInboxById');
const isRemovingReaction = ref(false);
// FORK: load + scroll + pulse when opening the quoted original
const { scrollToMessage: locateReplyMessage, isLocating } =
  useScrollToConversationMessage({ conversationId });

// FORK: Evolution Go/Node inbound delete highlight
const isDeleted = computed(() => Boolean(contentAttributes.value?.deleted));

// FORK: WhatsApp-like message forward badge
const isForwarded = computed(() => {
  const attrs = contentAttributes.value || {};
  return Boolean(attrs.forwarded || attrs.Forwarded);
});

// FORK: Evolution Go edited message badge (attrs or legacy content prefix)
const EDITED_PREFIX = 'Edited message:\n\n';
const isEdited = computed(() => {
  const attrs = contentAttributes.value || {};
  if (attrs.edited || attrs.Edited) return true;
  return String(content?.value || '').startsWith(EDITED_PREFIX);
});

// FORK: Evolution Go/Node WhatsApp reactions
const reactionInbox = computed(() => {
  if (!inboxId?.value) return null;
  return getInboxById.value?.(inboxId.value) || null;
});

const canReactOnChip = computed(() => {
  if (!inboxSupportsReactions(reactionInbox.value)) return false;
  return messageCanReceiveReaction({
    source_id: sourceId?.value,
    private: isPrivate?.value,
    content_attributes: contentAttributes?.value,
    status: status?.value,
  });
});

const reactionChips = computed(() => {
  const attrs = contentAttributes.value || {};
  return buildReactionChips(attrs.reactions || []);
});

const removeBusinessReaction = async chip => {
  if (!canReactOnChip.value || !chip?.isMine || isRemovingReaction.value) return;

  const snapshotAttrs = {
    ...(contentAttributes.value || {}),
  };
  const currentMessage = {
    id: messageId.value,
    conversation_id: conversationId.value,
    content_attributes: snapshotAttrs,
    source_id: sourceId.value,
  };
  const optimistic = applyOptimisticReaction(currentMessage, 'remove');
  store.dispatch('updateMessage', optimistic);

  isRemovingReaction.value = true;
  try {
    const response = await sendWhatsappReaction({
      conversationId: conversationId.value,
      messageId: messageId.value,
      reaction: 'remove',
    });
    if (response.data?.id) {
      store.dispatch('updateMessage', response.data);
    }
    useAlert(t('CONVERSATION.CONTEXT_MENU.REACTION_REMOVED'));
  } catch (error) {
    store.dispatch('updateMessage', {
      ...currentMessage,
      content_attributes: snapshotAttrs,
    });
    const detail = extractReactionErrorMessage(error);
    useAlert(
      detail
        ? t('CONVERSATION.CONTEXT_MENU.REACTION_FAILED_DETAIL', { detail })
        : t('CONVERSATION.CONTEXT_MENU.REACTION_FAILED')
    );
  } finally {
    isRemovingReaction.value = false;
  }
};

// FORK: Evolution Go/Node inbound delete highlight
const deletedNotice = computed(() => {
  const attrs = contentAttributes.value || {};
  if (
    attrs.deletedViaEvolutionGoWebhook ||
    attrs.deleted_via_evolution_go_webhook ||
    attrs.deletedViaEvolutionWebhook ||
    attrs.deleted_via_evolution_webhook
  ) {
    return t('CONVERSATION.DELETED_BY_CONTACT_NOTICE');
  }

  return t('CONVERSATION.DELETED_MESSAGE_NOTICE');
});

const varaintBaseMap = {
  [MESSAGE_VARIANTS.AGENT]: 'bg-n-solid-blue text-n-slate-12',
  [MESSAGE_VARIANTS.PRIVATE]:
    'bg-n-solid-amber text-n-amber-12 [&_.prosemirror-mention-node]:font-semibold',
  [MESSAGE_VARIANTS.USER]: 'bg-n-slate-4 text-n-slate-12',
  [MESSAGE_VARIANTS.ACTIVITY]: 'bg-n-alpha-1 text-n-slate-11 text-sm',
  [MESSAGE_VARIANTS.BOT]: 'bg-n-solid-iris text-n-slate-12',
  [MESSAGE_VARIANTS.TEMPLATE]: 'bg-n-solid-iris text-n-slate-12',
  [MESSAGE_VARIANTS.ERROR]: 'bg-n-ruby-4 text-n-ruby-12',
  [MESSAGE_VARIANTS.EMAIL]: 'w-full',
  [MESSAGE_VARIANTS.UNSUPPORTED]:
    'bg-n-solid-amber/70 border border-dashed border-n-amber-12 text-n-amber-12',
  // FORK: Evolution Go/Node inbound delete highlight
  [MESSAGE_VARIANTS.DELETED]:
    'bg-n-ruby-3 border border-n-ruby-7 text-n-ruby-12',
};

const orientationMap = {
  [ORIENTATION.LEFT]:
    'left-bubble rounded-xl ltr:rounded-bl-sm rtl:rounded-br-sm',
  [ORIENTATION.RIGHT]:
    'right-bubble rounded-xl ltr:rounded-br-sm rtl:rounded-bl-sm',
  [ORIENTATION.CENTER]: 'rounded-md',
};

const flexOrientationClass = computed(() => {
  const map = {
    [ORIENTATION.LEFT]: 'justify-start',
    [ORIENTATION.RIGHT]: 'justify-end',
    [ORIENTATION.CENTER]: 'justify-center',
  };

  return map[orientation.value];
});

const messageClass = computed(() => {
  const classToApply = [varaintBaseMap[variant.value]];

  if (variant.value !== MESSAGE_VARIANTS.ACTIVITY) {
    classToApply.push(orientationMap[orientation.value]);
  } else {
    classToApply.push('rounded-lg');
  }

  return classToApply;
});

const scrollToMessage = () => {
  if (!inReplyTo?.value?.id || isLocating.value) return;
  locateReplyMessage(inReplyTo.value);
};

const shouldShowMeta = computed(
  () =>
    !props.hideMeta &&
    !shouldGroupWithNext.value &&
    variant.value !== MESSAGE_VARIANTS.ACTIVITY
);

const replyToPreview = computed(() => {
  if (!inReplyTo?.value) return '';

  // FORK: loading stub while parent is fetched outside the lazy window
  if (inReplyTo.value.replyPreviewState === 'loading') {
    return t('CONVERSATION.REPLY_MESSAGE_LOADING');
  }

  const { content, attachments } = inReplyTo.value;

  if (content) return new MessageFormatter(content).formattedMessage;
  if (attachments?.length) {
    const firstAttachment = attachments[0];
    const fileType = firstAttachment.fileType ?? firstAttachment.file_type;

    return t(`CHAT_LIST.ATTACHMENTS.${fileType}.CONTENT`);
  }

  return t('CONVERSATION.REPLY_MESSAGE_NOT_FOUND');
});
</script>

<template>
  <div
    class="text-sm min-w-0"
    :class="[
      messageClass,
      {
        'max-w-lg': variant !== MESSAGE_VARIANTS.EMAIL,
      },
    ]"
  >
    <div
      v-if="inReplyTo"
      class="p-2 -mx-1 mb-2 rounded-lg cursor-pointer bg-n-alpha-black1 transition-opacity"
      :class="{ 'opacity-60 pointer-events-none': isLocating }"
      :title="t('CONVERSATION.REPLY_MESSAGE_CLICK_HINT')"
      @click="scrollToMessage"
    >
      <div
        v-dompurify-html="replyToPreview"
        class="prose prose-bubble line-clamp-2"
      />
    </div>
    <!-- FORK: Evolution Go/Node inbound delete highlight -->
    <div
      v-if="isDeleted"
      class="flex items-center gap-1.5 mb-2 text-xs font-medium text-n-ruby-11"
    >
      <Icon icon="i-lucide-trash-2" class="size-3.5 shrink-0" />
      <span>{{ deletedNotice }}</span>
    </div>
    <!-- FORK: WhatsApp-like message forward badge -->
    <div
      v-if="isForwarded"
      class="flex items-center gap-1 mb-1.5 text-xs font-medium text-n-slate-11"
    >
      <Icon icon="i-lucide-forward" class="size-3.5 shrink-0" />
      <span>{{ t('CONVERSATION.FORWARD.BADGE') }}</span>
    </div>
    <!-- FORK: Evolution Go edited message badge -->
    <div
      v-if="isEdited && !isDeleted"
      class="flex items-center gap-1 mb-1.5 text-xs font-medium text-n-slate-11"
    >
      <Icon icon="i-lucide-pencil" class="size-3.5 shrink-0" />
      <span>{{ t('CONVERSATION.EDIT.BADGE') }}</span>
    </div>
    <div :class="{ 'opacity-80': isDeleted }">
      <slot />
    </div>
    <!-- FORK: Evolution Go/Node WhatsApp reactions -->
    <div
      v-if="reactionChips.length"
      class="flex flex-wrap gap-1 mt-1.5"
      :class="flexOrientationClass"
    >
      <button
        v-for="chip in reactionChips"
        :key="chip.emoji"
        type="button"
        class="inline-flex items-center gap-0.5 rounded-full border bg-n-alpha-2 px-1.5 py-0.5 text-xs leading-none"
        :class="
          chip.isMine && canReactOnChip
            ? 'border-n-brand cursor-pointer ring-1 ring-n-brand/40'
            : 'border-n-strong cursor-default'
        "
        :disabled="Boolean(chip.isMine && canReactOnChip && isRemovingReaction)"
        :title="
          chip.isMine && canReactOnChip
            ? t('CONVERSATION.CONTEXT_MENU.REMOVE_REACTION')
            : undefined
        "
        @click.stop="
          chip.isMine && canReactOnChip && removeBusinessReaction(chip)
        "
      >
        <span>{{ chip.emoji }}</span>
        <span v-if="chip.count > 1" class="text-n-slate-11">{{
          chip.count
        }}</span>
      </button>
    </div>
    <MessageMeta
      v-if="shouldShowMeta"
      :class="[
        flexOrientationClass,
        variant === MESSAGE_VARIANTS.EMAIL ? 'px-3 pb-3' : '',
        // FORK: Evolution Go/Node inbound delete highlight (DELETED ruby meta)
        variant === MESSAGE_VARIANTS.PRIVATE
          ? 'text-n-amber-12/50'
          : variant === MESSAGE_VARIANTS.DELETED
            ? 'text-n-ruby-11'
            : 'text-n-slate-11',
      ]"
      class="mt-2"
    />
  </div>
</template>
