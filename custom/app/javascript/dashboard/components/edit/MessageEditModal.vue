<script setup>
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useStore } from 'dashboard/composables/store';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import {
  MAX_EDIT_LENGTH,
  stripEditedPrefix,
  editEvolutionGoMessage,
} from 'customDashboard/composables/useMessageEdit';

const props = defineProps({
  message: {
    type: Object,
    default: null,
  },
});

const emit = defineEmits(['done', 'close']);

const { t } = useI18n();
const store = useStore();
const dialogRef = ref(null);
const draft = ref('');
const isSaving = ref(false);

const conversationId = computed(
  () => props.message?.conversation_id ?? props.message?.conversationId
);
const messageId = computed(() => props.message?.id);

const canConfirm = computed(() => {
  const text = draft.value.trim();
  if (!text || isSaving.value) return false;
  if (text.length > MAX_EDIT_LENGTH) return false;
  const original = stripEditedPrefix(props.message?.content || '').trim();
  return text !== original;
});

const remaining = computed(() => MAX_EDIT_LENGTH - draft.value.length);

watch(
  () => props.message?.id,
  () => {
    draft.value = stripEditedPrefix(props.message?.content || '');
  }
);

const open = () => {
  draft.value = stripEditedPrefix(props.message?.content || '');
  dialogRef.value?.open();
};

const close = () => {
  dialogRef.value?.close();
};

const resetState = () => {
  draft.value = '';
  isSaving.value = false;
  emit('close');
};

const handleConfirm = async () => {
  if (!canConfirm.value || !conversationId.value || !messageId.value) return;

  isSaving.value = true;
  try {
    const response = await editEvolutionGoMessage({
      conversationId: conversationId.value,
      messageId: messageId.value,
      content: draft.value.trim(),
    });
    const updated = response.data;
    if (updated?.id) {
      store.dispatch('updateMessage', updated);
    }
    useAlert(t('CONVERSATION.EDIT.SUCCESS'));
    emit('done', updated);
    close();
  } catch (error) {
    const apiError = error?.response?.data?.error;
    useAlert(apiError || t('CONVERSATION.EDIT.FAILED'));
  } finally {
    isSaving.value = false;
  }
};

defineExpose({ open, close });
</script>

<template>
  <Dialog
    ref="dialogRef"
    type="edit"
    width="md"
    :title="$t('CONVERSATION.EDIT.TITLE')"
    :description="$t('CONVERSATION.EDIT.DESCRIPTION')"
    :confirm-button-label="$t('CONVERSATION.EDIT.CONFIRM')"
    :cancel-button-label="$t('CONVERSATION.EDIT.CANCEL')"
    :disable-confirm-button="!canConfirm"
    :is-loading="isSaving"
    @confirm="handleConfirm"
    @close="resetState"
  >
    <div class="flex flex-col gap-2">
      <textarea
        v-model="draft"
        rows="5"
        class="w-full resize-y rounded-lg border border-n-strong bg-n-background px-3 py-2 text-sm text-n-slate-12 outline-none focus:border-n-brand"
        :placeholder="$t('CONVERSATION.EDIT.PLACEHOLDER')"
        :maxlength="MAX_EDIT_LENGTH"
      />
      <p
        class="text-xs"
        :class="remaining < 0 ? 'text-n-ruby-11' : 'text-n-slate-11'"
      >
        {{ $t('CONVERSATION.EDIT.CHAR_HINT', { count: remaining }) }}
      </p>
    </div>
  </Dialog>
</template>
