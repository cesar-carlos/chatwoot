<script>
import { useAlert } from 'dashboard/composables';
import { mapGetters } from 'vuex';
import { useMessageFormatter } from 'shared/composables/useMessageFormatter';
import ContextMenu from 'dashboard/components/ui/ContextMenu.vue';
import AddCannedModal from 'dashboard/routes/dashboard/settings/canned/AddCanned.vue';
import { useSnakeCase } from 'dashboard/composables/useTransformKeys';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import { conversationUrl, frontendURL } from '../../../helper/URLHelper';
import {
  ACCOUNT_EVENTS,
  CONVERSATION_EVENTS,
} from '../../../helper/AnalyticsHelper/events';
import MenuItem from '../../../components/widgets/conversation/contextMenu/menuItem.vue';
import { useTrack } from 'dashboard/composables';
import NextButton from 'dashboard/components-next/button/Button.vue';
// FORK: Evolution Go/Node reactions
import MessageApi from 'dashboard/api/inbox/message';
import {
  inboxSupportsReactions,
  applyOptimisticReaction,
} from 'customDashboard/composables/useMessageReactions';
// FORK: WhatsApp-like message forward
import { inboxSupportsForward, messageCanBeForwarded } from 'customDashboard/composables/useMessageForward';
import MessageForwardModal from 'customDashboard/components/forward/MessageForwardModal.vue';
// FORK: Evolution Go edit outgoing message
import {
  inboxSupportsMessageEdit,
  messageCanBeEdited,
} from 'customDashboard/composables/useMessageEdit';
import MessageEditModal from 'customDashboard/components/edit/MessageEditModal.vue';

const EVOLUTION_GO_REACTION_EMOJIS = ['👍', '❤️', '😂', '😮', '😢', '🙏'];

export default {
  components: {
    AddCannedModal,
    MenuItem,
    ContextMenu,
    NextButton,
    MessageForwardModal,
    MessageEditModal,
  },
  props: {
    message: {
      type: Object,
      required: true,
    },
    isOpen: {
      type: Boolean,
      default: false,
    },
    enabledOptions: {
      type: Object,
      default: () => ({}),
    },
    contextMenuPosition: {
      type: Object,
      default: () => ({}),
    },
    hideButton: {
      type: Boolean,
      default: false,
    },
    inboxId: {
      type: Number,
      default: null,
    },
  },
  emits: ['open', 'close', 'replyTo'],
  setup() {
    const { getPlainText } = useMessageFormatter();

    return {
      getPlainText,
      evolutionGoReactionEmojis: EVOLUTION_GO_REACTION_EMOJIS,
    };
  },
  data() {
    return {
      isCannedResponseModalOpen: false,
      showDeleteModal: false,
      isSendingReaction: false,
    };
  },
  computed: {
    ...mapGetters({
      getAccount: 'accounts/getAccount',
      currentAccountId: 'getCurrentAccountId',
      getUISettings: 'getUISettings',
      getInboxById: 'inboxes/getInbox',
    }),
    plainTextContent() {
      return this.getPlainText(this.messageContent);
    },
    conversationId() {
      return this.message.conversation_id ?? this.message.conversationId;
    },
    messageId() {
      return this.message.id;
    },
    messageContent() {
      return this.message.content;
    },
    contentAttributes() {
      return useSnakeCase(
        this.message.content_attributes ?? this.message.contentAttributes
      );
    },
    messageSourceId() {
      return this.message.source_id || this.message.sourceId;
    },
    inbox() {
      if (!this.inboxId) return null;
      return this.getInboxById(this.inboxId) || null;
    },
    isWhatsAppSyncDeleteEnabled() {
      const inbox = this.inbox;
      if (!inbox || inbox.channel_type !== 'Channel::Whatsapp') return false;

      const provider = inbox.provider;
      if (provider !== 'evolution_go' && provider !== 'evolution') return false;

      // Admins get full provider_config; agents get top-level sync_delete_to_whatsapp.
      const config = inbox.provider_config || inbox.providerConfig || {};
      return (
        config.sync_delete_to_whatsapp === true ||
        inbox.sync_delete_to_whatsapp === true
      );
    },
    // FORK: Evolution Go/Node reactions
    canReactWithEvolutionGo() {
      return (
        inboxSupportsReactions(this.inbox) && Boolean(this.messageSourceId)
      );
    },
    // FORK: WhatsApp-like message forward
    canForwardMessage() {
      return (
        Boolean(this.enabledOptions.forward) &&
        inboxSupportsForward(this.inbox) &&
        messageCanBeForwarded(this.message)
      );
    },
    // FORK: Evolution Go edit outgoing message
    canEditMessage() {
      return (
        inboxSupportsMessageEdit(this.inbox) && messageCanBeEdited(this.message)
      );
    },
    deleteConfirmationMessage() {
      if (this.isWhatsAppSyncDeleteEnabled) {
        return this.$t(
          'CONVERSATION.CONTEXT_MENU.DELETE_CONFIRMATION.WHATSAPP_SYNC'
        );
      }

      return this.$t('CONVERSATION.CONTEXT_MENU.DELETE_CONFIRMATION.MESSAGE');
    },
  },
  methods: {
    async copyLinkToMessage() {
      const fullConversationURL =
        window.chatwootConfig.hostURL +
        frontendURL(
          conversationUrl({
            id: this.conversationId,
            accountId: this.currentAccountId,
          })
        );
      await copyTextToClipboard(
        `${fullConversationURL}?messageId=${this.messageId}`
      );
      useAlert(this.$t('CONVERSATION.CONTEXT_MENU.LINK_COPIED'));
      this.handleClose();
    },
    async handleCopy() {
      await copyTextToClipboard(this.plainTextContent);
      useAlert(this.$t('CONTACT_PANEL.COPY_SUCCESSFUL'));
      this.handleClose();
    },
    showCannedResponseModal() {
      useTrack(ACCOUNT_EVENTS.ADDED_TO_CANNED_RESPONSE);
      this.isCannedResponseModalOpen = true;
    },
    hideCannedResponseModal() {
      this.isCannedResponseModalOpen = false;
      this.handleClose();
    },
    handleOpen(e) {
      this.$emit('open', e);
    },
    handleClose(e) {
      this.$emit('close', e);
    },
    handleTranslate() {
      const { locale: accountLocale } = this.getAccount(this.currentAccountId);
      const agentLocale = this.getUISettings?.locale;
      const targetLanguage = agentLocale || accountLocale || 'en';
      this.$store.dispatch('translateMessage', {
        conversationId: this.conversationId,
        messageId: this.messageId,
        targetLanguage,
      });
      useTrack(CONVERSATION_EVENTS.TRANSLATE_A_MESSAGE);
      this.handleClose();
    },
    handleReplyTo() {
      this.$emit('replyTo', this.message);
      this.handleClose();
    },
    openDeleteModal() {
      this.handleClose();
      this.showDeleteModal = true;
    },
    async confirmDeletion() {
      try {
        await this.$store.dispatch('deleteMessage', {
          conversationId: this.conversationId,
          messageId: this.messageId,
        });
        useAlert(this.$t('CONVERSATION.SUCCESS_DELETE_MESSAGE'));
        this.handleClose();
      } catch (error) {
        useAlert(this.$t('CONVERSATION.FAIL_DELETE_MESSSAGE'));
      }
    },
    closeDeleteModal() {
      this.showDeleteModal = false;
    },
    // FORK: WhatsApp-like message forward
    openForwardModal() {
      this.handleClose();
      this.$nextTick(() => {
        this.$refs.forwardModal?.open();
      });
    },
    // FORK: Evolution Go edit outgoing message
    openEditModal() {
      this.handleClose();
      this.$nextTick(() => {
        this.$refs.editModal?.open();
      });
    },
    // FORK: Evolution Go/Node reactions (optimistic UI)
    async sendEvolutionGoReaction(reaction) {
      if (this.isSendingReaction || !this.canReactWithEvolutionGo) return;

      const snapshot =
        this.message.content_attributes ?? this.message.contentAttributes;
      const currentUserId = this.$store.getters.getCurrentUserID;
      const optimistic = applyOptimisticReaction(
        this.message,
        reaction,
        currentUserId
      );
      this.$store.dispatch('updateMessage', optimistic);

      this.isSendingReaction = true;
      try {
        const response = await MessageApi.evolutionGoReact(
          this.conversationId,
          this.messageId,
          reaction
        );
        const updated = response.data;
        if (updated?.id) {
          this.$store.dispatch('updateMessage', updated);
        }
        useAlert(this.$t('CONVERSATION.CONTEXT_MENU.REACTION_SENT'));
        this.handleClose();
      } catch (error) {
        this.$store.dispatch('updateMessage', {
          ...this.message,
          content_attributes: snapshot,
        });
        useAlert(this.$t('CONVERSATION.CONTEXT_MENU.REACTION_FAILED'));
      } finally {
        this.isSendingReaction = false;
      }
    },
  },
};
</script>

<template>
  <div class="context-menu">
    <!-- Add To Canned Responses -->
    <woot-modal
      v-if="isCannedResponseModalOpen && enabledOptions['cannedResponse']"
      v-model:show="isCannedResponseModalOpen"
      :on-close="hideCannedResponseModal"
    >
      <AddCannedModal
        :response-content="plainTextContent"
        :on-close="hideCannedResponseModal"
      />
    </woot-modal>
    <!-- Confirm Deletion -->
    <woot-delete-modal
      v-if="showDeleteModal && enabledOptions['delete']"
      v-model:show="showDeleteModal"
      class="context-menu--delete-modal"
      :on-close="closeDeleteModal"
      :on-confirm="confirmDeletion"
      :title="$t('CONVERSATION.CONTEXT_MENU.DELETE_CONFIRMATION.TITLE')"
      :message="deleteConfirmationMessage"
      :confirm-text="$t('CONVERSATION.CONTEXT_MENU.DELETE_CONFIRMATION.DELETE')"
      :reject-text="$t('CONVERSATION.CONTEXT_MENU.DELETE_CONFIRMATION.CANCEL')"
    />
    <NextButton
      v-if="!hideButton"
      ghost
      slate
      sm
      icon="i-lucide-ellipsis-vertical"
      class="invisible group-hover/context-menu:visible"
      @click="handleOpen"
    />
    <ContextMenu
      v-if="isOpen && !isCannedResponseModalOpen"
      :x="contextMenuPosition.x"
      :y="contextMenuPosition.y"
      @close="handleClose"
    >
      <div class="menu-container">
        <MenuItem
          v-if="enabledOptions['replyTo']"
          :option="{
            icon: 'arrow-reply',
            label: $t('CONVERSATION.CONTEXT_MENU.REPLY_TO'),
          }"
          variant="icon"
          @click.stop="handleReplyTo"
        />
        <MenuItem
          v-if="enabledOptions['copy']"
          :option="{
            icon: 'clipboard',
            label: $t('CONVERSATION.CONTEXT_MENU.COPY'),
          }"
          variant="icon"
          @click.stop="handleCopy"
        />
        <MenuItem
          v-if="enabledOptions['translate']"
          :option="{
            icon: 'translate',
            label: $t('CONVERSATION.CONTEXT_MENU.TRANSLATE'),
          }"
          variant="icon"
          @click.stop="handleTranslate"
        />
        <!-- FORK: Evolution Go reactions -->
        <template v-if="canReactWithEvolutionGo">
          <hr />
          <div class="px-2 py-1 text-xs text-n-slate-11">
            {{ $t('CONVERSATION.CONTEXT_MENU.REACT') }}
          </div>
          <div class="flex flex-wrap gap-1 px-2 pb-2">
            <button
              v-for="emoji in evolutionGoReactionEmojis"
              :key="emoji"
              type="button"
              class="rounded-md px-1.5 py-1 text-base hover:bg-n-alpha-2 disabled:opacity-50"
              :disabled="isSendingReaction"
              @click.stop="sendEvolutionGoReaction(emoji)"
            >
              {{ emoji }}
            </button>
            <button
              type="button"
              class="rounded-md px-1.5 py-1 text-xs text-n-slate-11 hover:bg-n-alpha-2 disabled:opacity-50"
              :disabled="isSendingReaction"
              @click.stop="sendEvolutionGoReaction('remove')"
            >
              {{ $t('CONVERSATION.CONTEXT_MENU.REMOVE_REACTION') }}
            </button>
          </div>
        </template>
        <!-- FORK: WhatsApp-like message forward -->
        <MenuItem
          v-if="canForwardMessage"
          :option="{
            icon: 'arrow-forward',
            label: $t('CONVERSATION.CONTEXT_MENU.FORWARD'),
          }"
          variant="icon"
          @click.stop="openForwardModal"
        />
        <!-- FORK: Evolution Go edit outgoing message -->
        <MenuItem
          v-if="canEditMessage"
          :option="{
            icon: 'edit',
            label: $t('CONVERSATION.CONTEXT_MENU.EDIT'),
          }"
          variant="icon"
          @click.stop="openEditModal"
        />
        <hr />
        <MenuItem
          v-if="enabledOptions['copyLink']"
          :option="{
            icon: 'link',
            label: $t('CONVERSATION.CONTEXT_MENU.COPY_PERMALINK'),
          }"
          variant="icon"
          @click.stop="copyLinkToMessage"
        />
        <MenuItem
          v-if="enabledOptions['cannedResponse']"
          :option="{
            icon: 'comment-add',
            label: $t('CONVERSATION.CONTEXT_MENU.CREATE_A_CANNED_RESPONSE'),
          }"
          variant="icon"
          @click.stop="showCannedResponseModal"
        />
        <hr v-if="enabledOptions['delete']" />
        <MenuItem
          v-if="enabledOptions['delete']"
          :option="{
            icon: 'delete',
            label: $t('CONVERSATION.CONTEXT_MENU.DELETE'),
          }"
          variant="icon"
          @click.stop="openDeleteModal"
        />
      </div>
    </ContextMenu>
    <!-- FORK: WhatsApp-like message forward -->
    <MessageForwardModal
      v-if="canForwardMessage"
      ref="forwardModal"
      :message="message"
      :inbox-id="inboxId"
    />
    <!-- FORK: Evolution Go edit outgoing message -->
    <MessageEditModal
      v-if="canEditMessage"
      ref="editModal"
      :message="message"
    />
  </div>
</template>

<style lang="scss" scoped>
.menu-container {
  @apply p-1 bg-n-background shadow-xl rounded-md;

  hr:first-child {
    @apply hidden;
  }

  hr {
    @apply m-1 border-b border-solid border-n-strong;
  }
}

.context-menu--delete-modal {
  :deep(.modal-container) {
    @apply max-w-[30rem];

    h2 {
      @apply font-medium text-base;
    }
  }
}
</style>
