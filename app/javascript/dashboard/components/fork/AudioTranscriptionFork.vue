<!-- FORK: extracted for merge-safe fork integration -->
<script setup>
import { computed, toValue } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'next/icon/Icon.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

const props = defineProps({
  section: {
    type: String,
    required: true,
    validator: value =>
      ['button', 'transcript', 'status', 'dialogs'].includes(value),
  },
  showTranscribedText: {
    type: Boolean,
    default: true,
  },
  showTranscribeButton: {
    type: Boolean,
    default: true,
  },
  isTranscribing: {
    type: Boolean,
    default: false,
  },
  displayError: {
    type: String,
    default: '',
  },
  transcriptText: {
    type: String,
    default: '',
  },
  setTokenMissingDialog: {
    type: Function,
    default: null,
  },
  setTokenInvalidDialog: {
    type: Function,
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

// v-bind from composables passes Ref/ComputedRef objects; unwrap to avoid always-truthy props
const isTranscribingActive = computed(() =>
  Boolean(toValue(props.isTranscribing))
);
const transcriptContent = computed(() => toValue(props.transcriptText) || '');
const errorMessage = computed(() => toValue(props.displayError) || '');

const setTokenMissingDialogRef = el => {
  props.setTokenMissingDialog?.(el);
};

const setTokenInvalidDialogRef = el => {
  props.setTokenInvalidDialog?.(el);
};
</script>

<template>
  <button
    v-if="section === 'button' && showTranscribeButton"
    class="p-0 border-0 size-6 grid place-content-center"
    :disabled="isTranscribingActive"
    :title="t('AUDIO.TRANSCRIBE')"
    @click="handleTranscribe"
  >
    <Icon
      class="size-3.5"
      :class="{ 'animate-pulse': isTranscribingActive }"
      icon="i-lucide-ear"
    />
  </button>

  <div
    v-else-if="
      section === 'transcript' && transcriptContent && showTranscribedText
    "
    class="text-n-slate-12 p-3 text-sm bg-n-alpha-1 rounded-lg w-full break-words"
  >
    {{ transcriptContent }}
  </div>

  <p
    v-else-if="section === 'status' && isTranscribingActive"
    class="text-xs text-n-slate-11 px-1"
  >
    {{ t('AUDIO.TRANSCRIPTION.PROCESSING') }}
  </p>

  <p
    v-else-if="section === 'status' && errorMessage"
    class="text-xs text-n-ruby-11 px-1"
  >
    {{ errorMessage }}
  </p>

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
