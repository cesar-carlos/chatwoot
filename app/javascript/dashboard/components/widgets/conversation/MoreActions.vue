<script>
import { mapGetters } from 'vuex';
import { useAlert } from 'dashboard/composables';
import { emitter } from 'shared/helpers/mitt';

import EmailTranscriptModal from './EmailTranscriptModal.vue';
import VoiceCallModal from './VoiceCallModal.vue';
import ResolveAction from '../../buttons/ResolveAction.vue';
import ButtonV4 from 'dashboard/components-next/button/Button.vue';

import {
  CMD_MUTE_CONVERSATION,
  CMD_SEND_TRANSCRIPT,
  CMD_UNMUTE_CONVERSATION,
} from 'dashboard/helper/commandbar/events';

export default {
  components: {
    EmailTranscriptModal,
    VoiceCallModal,
    ResolveAction,
    ButtonV4,
  },
  data() {
    return {
      showEmailActionsModal: false,
      showVoiceCallModal: false,
      showWavoipAlert: false,
      wavoipError: '',
    };
  },
  computed: {
    ...mapGetters({
      currentChat: 'getSelectedChat',
      currentUser: 'getCurrentUser',
    }),
    hasWavoipToken() {
      return this.currentUser?.wavoip_token?.length > 0;
    },
  },
  mounted() {
    emitter.on(CMD_MUTE_CONVERSATION, this.mute);
    emitter.on(CMD_UNMUTE_CONVERSATION, this.unmute);
    emitter.on(CMD_SEND_TRANSCRIPT, this.toggleEmailActionsModal);
  },
  unmounted() {
    emitter.off(CMD_MUTE_CONVERSATION, this.mute);
    emitter.off(CMD_UNMUTE_CONVERSATION, this.unmute);
    emitter.off(CMD_SEND_TRANSCRIPT, this.toggleEmailActionsModal);
  },
  methods: {
    mute() {
      this.$store.dispatch('muteConversation', this.currentChat.id);
      useAlert(this.$t('CONTACT_PANEL.MUTED_SUCCESS'));
    },
    unmute() {
      this.$store.dispatch('unmuteConversation', this.currentChat.id);
      useAlert(this.$t('CONTACT_PANEL.UNMUTED_SUCCESS'));
    },
    toggleEmailActionsModal() {
      this.showEmailActionsModal = !this.showEmailActionsModal;
    },
    toggleVoiceCallModal() {
      if (!this.hasWavoipToken) {
        this.wavoipError = '';
        this.showWavoipAlert = true;
        return;
      }
      this.showVoiceCallModal = !this.showVoiceCallModal;
    },
    closeWavoipAlert() {
      this.showWavoipAlert = false;
      this.wavoipError = '';
    },
    assignAgent() {
      const {
        account_id,
        availability_status,
        available_name,
        email,
        id,
        name,
        role,
        avatar_url,
      } = this.currentUser;

      const selfAssign = {
        account_id,
        availability_status,
        available_name,
        email,
        id,
        name,
        role,
        thumbnail: avatar_url,
      };

      const agentId = selfAssign ? selfAssign.id : 0;
      this.$store.dispatch('setCurrentChatAssignee', selfAssign);

      this.$store
        .dispatch('assignAgent', {
          conversationId: this.currentChat.id,
          agentId,
        })
        .then(() => {
          useAlert(this.$t('CONVERSATION.CHANGE_AGENT'));
        });
    },
    handleVoiceCallError(error) {
      this.wavoipError = error;
      this.showWavoipAlert = true;
      this.showVoiceCallModal = false;
    },
  },
};
</script>

<template>
  <div class="relative flex items-center gap-2 actions--container">
    <ButtonV4
      v-if="!currentChat.muted"
      v-tooltip="$t('CONTACT_PANEL.MUTE_CONTACT')"
      size="sm"
      variant="ghost"
      color="slate"
      icon="i-lucide-volume-off"
      @click="mute"
    />
    <ButtonV4
      v-else
      v-tooltip.left="$t('CONTACT_PANEL.UNMUTE_CONTACT')"
      size="sm"
      variant="ghost"
      color="slate"
      icon="i-lucide-volume-1"
      @click="unmute"
    />
    <ButtonV4
      v-tooltip="$t('CONTACT_PANEL.SEND_TRANSCRIPT')"
      size="sm"
      variant="ghost"
      color="slate"
      icon="i-lucide-share"
      @click="toggleEmailActionsModal"
    />
    <ButtonV4
      v-tooltip="$t('CONVERSATION.ASSIGNMENT.ASSIGN')"
      size="sm"
      variant="ghost"
      color="slate"
      icon="i-lucide-user-round"
      @click="assignAgent"
    />
    <ButtonV4
      v-tooltip="$t('CONVERSATION.VOICE_CALL')"
      size="sm"
      variant="ghost"
      color="slate"
      icon="i-lucide-phone"
      @click="toggleVoiceCallModal"
    />

    <ResolveAction
      :conversation-id="currentChat.id"
      :status="currentChat.status"
    />
    <EmailTranscriptModal
      v-if="showEmailActionsModal"
      :show="showEmailActionsModal"
      :current-chat="currentChat"
      @cancel="toggleEmailActionsModal"
    />
    <VoiceCallModal
      v-if="showVoiceCallModal"
      :show="showVoiceCallModal"
      :current-chat="currentChat"
      @close="showVoiceCallModal = false"
      @error="handleVoiceCallError"
    />

    <!-- Alerta de Token Wavoip ou Erro de Chamada -->
    <div
      v-if="showWavoipAlert"
      class="fixed inset-0 flex items-center justify-center z-50 bg-black bg-opacity-50"
    >
      <div
        class="bg-white dark:bg-slate-800 rounded-lg p-6 shadow-lg max-w-md w-full mx-4 relative"
      >
        <div class="mb-4">
          <h3 class="text-lg font-semibold text-slate-800 dark:text-slate-200">
            {{ $t('CONVERSATION.VOICE_CALL_MODAL.ERROR.TITLE') }}
          </h3>
        </div>
        <div class="mb-6">
          <p class="text-slate-700 dark:text-slate-300">
            {{
              wavoipError ||
              $t('CONVERSATION.VOICE_CALL_MODAL.ERROR.NO_WAVOIP_TOKEN')
            }}
          </p>
        </div>
        <div class="flex justify-end">
          <button
            class="px-4 py-2 bg-woot-500 text-white rounded hover:bg-woot-600 transition-colors"
            @click="closeWavoipAlert"
          >
            {{ $t('CONVERSATION.VOICE_CALL_MODAL.ERROR.CLOSE') }}
          </button>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped lang="scss">
.more--button {
  @apply items-center flex ml-2 rtl:ml-0 rtl:mr-2;
}

.dropdown-pane {
  @apply -right-2 top-12;
}

.icon {
  @apply mr-1 rtl:mr-0 rtl:ml-1 min-w-[1rem];
}
</style>
