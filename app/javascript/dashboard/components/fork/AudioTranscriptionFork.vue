<!-- FORK: extracted for merge-safe fork integration -->
<script setup>
import { useI18n } from 'vue-i18n';
import Icon from 'next/icon/Icon.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

const props = defineProps({
  section: {
    type: String,
    required: true,
    validator: value => ['button', 'transcript', 'dialogs'].includes(value),
  },
  showTranscribedText: {
    type: Boolean,
    default: true,
  },
  isTranscribing: {
    type: Boolean,
    default: false,
  },
  transcriptText: {
    type: String,
    default: '',
  },
  tokenMissingDialogRef: {
    type: Object,
    default: null,
  },
  tokenInvalidDialogRef: {
    type: Object,
    default: null,
  },
  handleTranscribe: {
    type: Function,
    default: () => {},
  },
  goToSettings: {
    type: Function,
    default: () => {},
  },
});

const { t } = useI18n();

const setTokenMissingDialogRef = el => {
  if (props.tokenMissingDialogRef) {
    props.tokenMissingDialogRef.value = el;
  }
};

const setTokenInvalidDialogRef = el => {
  if (props.tokenInvalidDialogRef) {
    props.tokenInvalidDialogRef.value = el;
  }
};
</script>

<template>
  <button
    v-if="section === 'button'"
    class="p-0 border-0 size-6 grid place-content-center"
    :disabled="isTranscribing"
    :title="t('AUDIO.TRANSCRIBE')"
    @click="handleTranscribe"
  >
    <Icon
      class="size-3.5"
      :class="{ 'animate-pulse': isTranscribing }"
      icon="i-lucide-ear"
    />
  </button>

  <div
    v-else-if="
      section === 'transcript' && transcriptText && showTranscribedText
    "
    class="text-n-slate-12 p-3 text-sm bg-n-alpha-1 rounded-lg w-full break-words"
  >
    {{ transcriptText }}
  </div>

  <template v-else-if="section === 'dialogs'">
    <Dialog
      :ref="setTokenMissingDialogRef"
      type="alert"
      width="md"
      :title="t('AUDIO.TOKEN_MISSING.TITLE')"
      :description="t('AUDIO.TOKEN_MISSING.MESSAGE')"
      :confirm-button-label="t('AUDIO.TOKEN_MISSING.GO_TO_SETTINGS')"
      :cancel-button-label="t('AUDIO.TOKEN_MISSING.CANCEL')"
      @confirm="goToSettings"
    />

    <Dialog
      :ref="setTokenInvalidDialogRef"
      type="alert"
      width="md"
      :title="t('AUDIO.TOKEN_INVALID.TITLE')"
      :description="t('AUDIO.TOKEN_INVALID.MESSAGE')"
      :confirm-button-label="t('AUDIO.TOKEN_INVALID.GO_TO_SETTINGS')"
      :cancel-button-label="t('AUDIO.TOKEN_INVALID.CANCEL')"
      @confirm="goToSettings"
    />
  </template>
</template>
