<script setup>
import { ref, onMounted, onUnmounted } from 'vue';
import { useToast } from '@/dashboard/helper/toast';
import Wavoip from 'wavoip-api';
import Icon from '@/dashboard/components-next/icon/Icon.vue';

const props = defineProps({
  phoneNumber: {
    type: String,
    required: true,
  },
});

const toast = useToast();
const isCallActive = ref(false);
const showIncomingCall = ref(false);
const incomingCallData = ref(null);
const wavoip = new Wavoip();

// Som de chamada
const ringtone = new Audio('/sounds/ring.mp3');
const playRingtone = () => {
  ringtone.loop = true;
  ringtone.play();
};

const stopRingtone = () => {
  ringtone.pause();
  ringtone.currentTime = 0;
};

// Inicializa o listener de chamadas recebidas
const initializeCallListener = () => {
  const instance = wavoip.connect(process.env.WAVOIP_TOKEN);

  instance.socket.on('incomingCall', callData => {
    incomingCallData.value = callData;
    showIncomingCall.value = true;
    playRingtone();
  });
};

// Atender chamada
const handleAnswerCall = () => {
  try {
    if (incomingCallData.value) {
      wavoip.answerCall(incomingCallData.value.callId);
      isCallActive.value = true;
      showIncomingCall.value = false;
      stopRingtone();
      toast.success('Chamada atendida com sucesso!');
    }
  } catch (error) {
    toast.error('Erro ao atender a chamada');
  }
};

// Rejeitar chamada
const handleRejectCall = () => {
  try {
    if (incomingCallData.value) {
      wavoip.rejectCall(incomingCallData.value.callId);
      showIncomingCall.value = false;
      stopRingtone();
      toast.info('Chamada rejeitada');
    }
  } catch (error) {
    toast.error('Erro ao rejeitar a chamada');
  }
};

const handleStartCall = async () => {
  try {
    const instance = wavoip.connect(process.env.WAVOIP_TOKEN);

    instance.socket.on('connect', () => {
      instance.callStart({
        whatsappid: props.phoneNumber,
      });
      isCallActive.value = true;
      toast.success('Chamada iniciada com sucesso!');
    });

    instance.socket.on('error', error => {
      toast.error(`Erro na chamada: ${error.message}`);
      isCallActive.value = false;
    });
  } catch (error) {
    toast.error('Não foi possível iniciar a chamada');
  }
};

// Inicializa o listener quando o componente é montado
onMounted(() => {
  initializeCallListener();
});

// Limpa o listener e para o ringtone quando o componente é desmontado
onUnmounted(() => {
  stopRingtone();
});
</script>

<template>
  <div class="flex flex-col items-end my-4">
    <div class="flex items-center justify-center w-full">
      <button
        class="p-2 rounded-full hover:bg-n-alpha-1 transition-colors"
        :title="$t('CONVERSATION.START_VOICE_CALL')"
        @click="handleStartCall"
      >
        <Icon icon="i-lucide-phone" class="size-4 text-n-slate-11" />
      </button>
    </div>

    <!-- Modal de chamada recebida -->
    <div
      v-if="showIncomingCall"
      class="fixed inset-0 flex items-center justify-center bg-black bg-opacity-50 z-50"
    >
      <div class="bg-white rounded-lg p-6 shadow-lg max-w-sm w-full mx-4">
        <div class="text-center mb-6">
          <Icon
            icon="i-lucide-phone-incoming"
            class="size-12 text-green-500 mx-auto mb-4 animate-bounce"
          />
          <h3 class="text-lg font-semibold mb-2">
            {{ $t('CONVERSATION.INCOMING_CALL') }}
          </h3>
          <p class="text-gray-600">
            {{ incomingCallData?.caller || $t('CONVERSATION.UNKNOWN_CALLER') }}
          </p>
        </div>

        <div class="flex justify-center space-x-4">
          <button
            class="px-6 py-2 bg-red-500 text-white rounded-full hover:bg-red-600 transition-colors flex items-center"
            @click="handleRejectCall"
          >
            <Icon icon="i-lucide-phone-off" class="size-4 mr-2" />
            {{ $t('CONVERSATION.REJECT_CALL') }}
          </button>
          <button
            class="px-6 py-2 bg-green-500 text-white rounded-full hover:bg-green-600 transition-colors flex items-center"
            @click="handleAnswerCall"
          >
            <Icon icon="i-lucide-phone" class="size-4 mr-2" />
            {{ $t('CONVERSATION.ANSWER_CALL') }}
          </button>
        </div>
      </div>
    </div>
  </div>
</template>
