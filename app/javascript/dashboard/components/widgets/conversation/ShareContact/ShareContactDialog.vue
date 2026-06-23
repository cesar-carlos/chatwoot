<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import ShareContactForm from './ShareContactForm.vue';

defineProps({
  conversationContact: {
    type: Object,
    default: () => ({}),
  },
});

const emit = defineEmits(['share']);

const { t } = useI18n();

const dialogRef = ref(null);
const selectedContactId = ref(null);
const selectedContact = ref(null);
const isSharing = ref(false);

const disableConfirmButton = computed(
  () => !selectedContactId.value || isSharing.value
);

const resetSelection = () => {
  selectedContactId.value = null;
  selectedContact.value = null;
};

const handleSelectContact = contact => {
  selectedContactId.value = contact?.id ?? null;
  selectedContact.value = contact;
};

const handleShare = () => {
  if (!selectedContact.value) return;
  emit('share', selectedContact.value);
};

const handleQuickShare = contact => {
  handleSelectContact(contact);
  handleShare();
};

const handleClose = () => {
  resetSelection();
};

const open = () => {
  resetSelection();
  dialogRef.value?.open();
};

const close = () => {
  dialogRef.value?.close();
  resetSelection();
};

const setSharing = value => {
  isSharing.value = value;
};

defineExpose({ open, close, setSharing });
</script>

<template>
  <Dialog
    ref="dialogRef"
    type="edit"
    width="md"
    overflow-y-auto
    :title="t('CONVERSATION.SHARE_CONTACT.MODAL.TITLE')"
    :description="t('CONVERSATION.SHARE_CONTACT.MODAL.DESCRIPTION')"
    :confirm-button-label="t('CONVERSATION.SHARE_CONTACT.MODAL.CONFIRM')"
    :cancel-button-label="t('CONVERSATION.SHARE_CONTACT.MODAL.CANCEL')"
    :disable-confirm-button="disableConfirmButton"
    :is-loading="isSharing"
    @confirm="handleShare"
    @close="handleClose"
  >
    <ShareContactForm
      :conversation-contact="conversationContact"
      :selected-contact-id="selectedContactId"
      :is-sharing="isSharing"
      @select="handleSelectContact"
      @quick-share="handleQuickShare"
    />
  </Dialog>
</template>
