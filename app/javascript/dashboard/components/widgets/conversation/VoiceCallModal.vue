<script>
import { useToast } from '@/dashboard/helper/toast';
import Modal from '@/dashboard/components/Modal.vue';
import Wavoip from 'wavoip-api';
import { computed } from 'vue';
import { useStore } from 'dashboard/composables/store';
import ApiClient from '@/dashboard/api/ApiClient';

export default {
  components: {
    Modal,
  },
  props: {
    show: {
      type: Boolean,
      default: false,
    },
    currentChat: {
      type: Object,
      required: true,
    },
  },
  emits: ['close'],
  setup() {
    const toast = useToast();
    const store = useStore();
    const currentUser = computed(() => store.getters.getCurrentUser);
    return { toast, currentUser };
  },
  data() {
    return {
      displayNumber: '',
      isCallActive: false,
      wavoip: null,
      wavoipInstance: null,
      contactDetails: null,
      dialpadItems: [
        { digit: '1', letters: '', key: '1' },
        { digit: '2', letters: 'ABC', key: '2' },
        { digit: '3', letters: 'DEF', key: '3' },
        { digit: '4', letters: 'GHI', key: '4' },
        { digit: '5', letters: 'JKL', key: '5' },
        { digit: '6', letters: 'MNO', key: '6' },
        { digit: '7', letters: 'PQRS', key: '7' },
        { digit: '8', letters: 'TUV', key: '8' },
        { digit: '9', letters: 'WXYZ', key: '9' },
        { digit: '*', letters: '', key: '*' },
        { digit: '0', letters: '', key: '0' },
        { digit: '#', letters: '', key: '#' },
      ],
      isMuted: false,
      isConnecting: false,
      incomingCall: false,
      callStatus: 'idle', // idle, connecting, active, ended
    };
  },
  computed: {
    contactName() {
      return (
        this.contactDetails?.name ||
        this.currentChat?.meta?.sender?.name ||
        this.$t('CONVERSATION.UNKNOWN_CALLER')
      );
    },
    phoneNumber() {
      return (
        this.contactDetails?.phone_number ||
        this.currentChat?.meta?.sender?.phone_number ||
        ''
      );
    },
    contactAvatar() {
      return (
        this.contactDetails?.avatar_url ||
        this.currentChat?.meta?.sender?.avatar_url
      );
    },
  },
  mounted() {
    this.wavoip = new Wavoip();
    window.addEventListener('keydown', this.handleKeydown);
  },
  beforeUnmount() {
    if (this.wavoipInstance?.socket) {
      this.wavoipInstance.socket.disconnect();
    }
    window.removeEventListener('keydown', this.handleKeydown);
  },
  methods: {
    handleKeydown(event) {
      if (!this.show) return;

      const key = event.key.toLowerCase();

      // Teclas numéricas (0-9)
      if (/^[0-9]$/.test(key)) {
        this.appendNumber(key);
        return;
      }

      // Teclas especiais
      switch (key) {
        case '#':
        case '*':
        case '+':
          event.preventDefault();
          this.appendNumber(key === '+' ? '0' : key);
          break;
        case 'backspace':
          event.preventDefault();
          this.deleteLastNumber();
          break;
        case 'delete':
          event.preventDefault();
          this.clearNumber();
          break;
        case 'enter':
          event.preventDefault();
          if (!this.isCallActive) {
            this.startCall();
          } else {
            this.endCall();
          }
          break;
        case 'escape':
          event.preventDefault();
          this.handleClose();
          break;
        default:
          break;
      }
    },
    handleClose() {
      this.endCall();
      this.$emit('close');
    },
    appendNumber(number) {
      if (number) {
        this.displayNumber += number;
      }
    },
    clearNumber() {
      this.displayNumber = '';
    },
    deleteLastNumber() {
      this.displayNumber = this.displayNumber.slice(0, -1);
    },
    async startCall() {
      if (this.isCallActive) return;

      try {
        this.isCallActive = true;
        this.isConnecting = true;
        this.callStatus = 'connecting';

        if (!this.wavoip) {
          this.wavoip = new Wavoip();
        }

        const token = this.currentUser.wavoip_token;

        if (!token) {
          throw new Error(
            'Token do Wavoip não encontrado. Configure o token no seu perfil.'
          );
        }

        const cleanToken = token.replace(/^"|"$/g, '');
        this.wavoipInstance = await this.wavoip.connect(cleanToken);

        if (!this.wavoipInstance) {
          throw new Error('Falha ao conectar com Wavoip');
        }

        if (!this.wavoipInstance.socket) {
          throw new Error('Socket não inicializado');
        }

        this.wavoipInstance.socket.on('connect', () => {
          const number = this.displayNumber || this.phoneNumber;

          if (!number) {
            this.isCallActive = false;
            this.callStatus = 'idle';
            this.toast.error(this.$t('CONVERSATION.NO_NUMBER'));
            return;
          }

          this.wavoipInstance.callStart({
            whatsappid: number,
          });

          this.callStatus = 'active';
          this.toast.success(this.$t('CONVERSATION.CALL_STARTED'));
        });

        this.wavoipInstance.socket.on('incomingCall', () => {
          this.incomingCall = true;
          this.callStatus = 'incoming';
          this.toast.info(
            this.$t('CONVERSATION.VOICE_CALL_MODAL.CALL_WAITING')
          );
        });

        this.wavoipInstance.socket.on('callStart', () => {
          this.incomingCall = false;
          this.callStatus = 'active';
          this.toast.success(
            this.$t('CONVERSATION.VOICE_CALL_MODAL.CALL_ANSWERED')
          );
        });

        this.wavoipInstance.socket.on('callEnd', () => {
          this.isCallActive = false;
          this.incomingCall = false;
          this.callStatus = 'ended';
          this.toast.info(
            this.$t('CONVERSATION.VOICE_CALL_MODAL.CALL_ENDED_BY_OTHER')
          );
        });

        this.wavoipInstance.socket.on('error', error => {
          this.isCallActive = false;
          this.callStatus = 'idle';
          this.toast.error(
            `${this.$t('CONVERSATION.CALL_ERROR')}: ${error.message}`
          );
        });

        this.wavoipInstance.socket.on('disconnect', () => {
          this.isCallActive = false;
          this.callStatus = 'idle';
          this.toast.error(this.$t('CONVERSATION.CALL_DISCONNECTED'));
        });
      } catch (error) {
        this.isCallActive = false;
        this.callStatus = 'idle';
        this.toast.error(
          `${this.$t('CONVERSATION.CALL_FAILED')}: ${error.message}`
        );
      } finally {
        this.isConnecting = false;
      }
    },
    endCall() {
      try {
        if (this.wavoipInstance?.socket) {
          this.wavoipInstance.socket.disconnect();
        }
      } catch (error) {
        this.toast.error(this.$t('CONVERSATION.END_CALL_ERROR'));
      } finally {
        this.isCallActive = false;
        this.callStatus = 'idle';
      }
    },
    toggleMute() {
      if (!this.wavoipInstance || !this.isCallActive) {
        return;
      }

      try {
        this.isMuted = !this.isMuted;
        this.wavoipInstance.socket.emit('toggleMute', { muted: this.isMuted });

        if (this.isMuted) {
          this.toast.success(this.$t('CONVERSATION.VOICE_CALL_MODAL.MUTED'));
        } else {
          this.toast.success(this.$t('CONVERSATION.VOICE_CALL_MODAL.UNMUTED'));
        }
      } catch (error) {
        this.toast.error(
          this.$t('CONVERSATION.VOICE_CALL_MODAL.ERROR.MUTE_ERROR')
        );
      }
    },
    async fetchContactDetails() {
      try {
        const api = new ApiClient();
        const response = await api.get(
          `/api/v1/accounts/${this.currentChat.account_id}/contacts/${this.currentChat.meta.sender.id}`
        );
        if (response.data) {
          this.contactDetails = {
            ...this.currentChat.meta.sender,
            ...response.data,
          };
        }
      } catch (error) {
        // Ignora o erro silenciosamente
      }
    },
  },
};
</script>

<template>
  <div>
    <Modal
      :show="show"
      class="!max-w-[280px] !w-[280px] !inset-0 !m-auto !h-fit"
      @close="handleClose"
    >
      <div class="w-[280px] bg-white rounded-lg shadow-lg">
        <div class="p-4">
          <!-- Botão de fechar -->
          <div class="flex justify-end mb-4">
            <woot-button
              variant="clear"
              color-scheme="secondary"
              icon="close"
              @click="handleClose"
            />
          </div>

          <!-- Display Number Section -->
          <div class="text-center mb-1">
            <div class="flex flex-col items-center justify-center">
              <div class="w-12 h-12 rounded-full overflow-hidden mb-0.5">
                <img
                  :src="contactAvatar"
                  :alt="contactName"
                  class="w-full h-full object-cover"
                />
              </div>
              <div class="text-xl font-medium text-gray-800">
                {{ contactName }}
              </div>
              <span class="text-lg font-medium mt-0.5">
                {{ displayNumber || phoneNumber || '+1' }}
              </span>
              <div class="flex items-center gap-2 mt-0.5">
                <span
                  v-if="callStatus === 'connecting'"
                  class="text-sm text-blue-500 animate-pulse flex items-center gap-1"
                >
                  <div class="w-2 h-2 rounded-full bg-blue-500 animate-pulse" />
                  {{ $t('CONVERSATION.VOICE_CALL_MODAL.CONNECTING') }}
                </span>
                <span
                  v-else-if="callStatus === 'active'"
                  class="text-sm text-green-500 animate-pulse flex items-center gap-1"
                >
                  <div
                    class="w-2 h-2 rounded-full bg-green-500 animate-pulse"
                  />
                  {{ $t('CONVERSATION.VOICE_CALL_MODAL.IN_CALL') }}
                </span>
                <span
                  v-else-if="callStatus === 'incoming'"
                  class="text-sm text-yellow-500 animate-pulse flex items-center gap-1"
                >
                  <div
                    class="w-2 h-2 rounded-full bg-yellow-500 animate-pulse"
                  />
                  {{ $t('CONVERSATION.VOICE_CALL_MODAL.CALL_WAITING') }}
                </span>
                <span
                  v-else-if="callStatus === 'ended'"
                  class="text-sm text-gray-500 flex items-center gap-1"
                >
                  <div class="w-2 h-2 rounded-full bg-gray-500" />
                  {{ $t('CONVERSATION.VOICE_CALL_MODAL.CALL_ENDED_BY_OTHER') }}
                </span>
                <span
                  v-else
                  class="text-sm text-gray-500 flex items-center gap-1"
                >
                  <div class="w-2 h-2 rounded-full bg-gray-500" />
                  {{ $t('CONVERSATION.VOICE_CALL_MODAL.STATUS.READY') }}
                </span>
              </div>
            </div>
          </div>

          <!-- Dialpad Grid -->
          <div class="grid grid-cols-3 gap-4">
            <button
              v-for="(number, index) in dialpadItems"
              :key="index"
              class="aspect-square rounded-full bg-gray-100 hover:bg-gray-200 transition-colors flex flex-col items-center justify-center"
              @click="appendNumber(number.digit)"
            >
              <span class="text-lg font-medium text-gray-800">
                {{ number.digit }}
              </span>
              <span
                v-if="number.letters"
                class="text-[10px] text-gray-700 mt-0.5"
              >
                {{ number.letters }}
              </span>
            </button>
          </div>

          <!-- Action Buttons -->
          <div class="flex justify-between items-center">
            <button
              class="w-10 h-10 rounded-full hover:bg-gray-100 flex items-center justify-center transition-colors"
              :class="{
                'bg-red-100 hover:bg-red-200': isMuted,
                'hover:bg-gray-100': !isMuted,
              }"
              :title="
                isMuted
                  ? $t('CONVERSATION.VOICE_CALL_MODAL.UNMUTE')
                  : $t('CONVERSATION.VOICE_CALL_MODAL.MUTE')
              "
              @click="toggleMute"
            >
              <i
                class="w-5 h-5"
                :class="{
                  'i-lucide-mic-off text-red-600': isMuted,
                  'i-lucide-mic text-gray-600': !isMuted,
                }"
              />
            </button>

            <button
              class="w-14 h-14 rounded-full transition-colors flex items-center justify-center"
              :class="[
                isCallActive
                  ? 'bg-red-500 hover:bg-red-600'
                  : 'bg-green-500 hover:bg-green-600',
              ]"
              @click="isCallActive ? endCall() : startCall()"
            >
              <i class="w-7 h-7 text-white i-lucide-phone" />
            </button>

            <button
              class="w-10 h-10 rounded-full hover:bg-gray-100 flex items-center justify-center"
              :title="$t('CONVERSATION.VOICE_CALL_MODAL.DELETE')"
              @click="deleteLastNumber"
            >
              <i class="w-5 h-5 text-gray-800 i-lucide-trash-2" />
            </button>
          </div>
        </div>
      </div>
    </Modal>
  </div>
</template>

<style scoped>
.backdrop-blur-sm {
  backdrop-filter: blur(8px);
}
</style>
