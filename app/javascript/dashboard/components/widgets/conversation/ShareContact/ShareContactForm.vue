<script setup>
import { ref, computed } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { debounce } from '@chatwoot/utils';
import { useAlert } from 'dashboard/composables';

import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import { createContactSearcher } from 'dashboard/components-next/NewConversation/helpers/composeConversationHelper';

const props = defineProps({
  conversationContact: {
    type: Object,
    default: () => ({}),
  },
  selectedContactId: {
    type: [Number, String, null],
    default: null,
  },
  isSharing: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['select', 'quickShare']);

const { t } = useI18n();
const route = useRoute();
const searchContacts = createContactSearcher();

const contactOptions = ref([]);
const isSearching = ref(false);

const conversationPhoneNumber = computed(
  () =>
    props.conversationContact?.phone_number ||
    props.conversationContact?.phoneNumber ||
    ''
);

const showConversationShortcut = computed(
  () => !!props.conversationContact?.id
);

const editContactPath = computed(() => {
  if (!props.conversationContact?.id) return '';
  return `/app/accounts/${route.params.accountId}/contacts/${props.conversationContact.id}`;
});

const mapContactOption = contact => ({
  id: contact.id,
  label: contact.name,
  value: contact.id,
  meta: {
    thumbnail: contact.thumbnail,
    phoneNumber: contact.phoneNumber,
    email: contact.email,
  },
});

const onSearch = debounce(async query => {
  isSearching.value = true;
  try {
    const results = await searchContacts(query);
    if (results === null) return;

    contactOptions.value = (results || [])
      .filter(contact => contact.phoneNumber)
      .map(mapContactOption);
  } catch {
    useAlert(t('CONVERSATION.SHARE_CONTACT.ERROR'));
  } finally {
    isSearching.value = false;
  }
}, 300);

const onSelect = contactId => {
  const contact = contactOptions.value.find(option => option.id === contactId);
  if (!contact) return;

  emit('select', {
    id: contact.id,
    name: contact.label,
    phone_number: contact.meta.phoneNumber,
    phoneNumber: contact.meta.phoneNumber,
    thumbnail: contact.meta.thumbnail,
  });
};

const onQuickShare = () => {
  if (!conversationPhoneNumber.value) return;

  emit('quickShare', {
    id: props.conversationContact.id,
    name: props.conversationContact.name,
    phone_number: conversationPhoneNumber.value,
    phoneNumber: conversationPhoneNumber.value,
    thumbnail:
      props.conversationContact.thumbnail ||
      props.conversationContact.avatar_url,
  });
};
</script>

<template>
  <div class="flex flex-col gap-4">
    <div v-if="showConversationShortcut" class="flex flex-col gap-2">
      <span class="text-sm text-n-slate-12">
        {{ t('CONVERSATION.SHARE_CONTACT.MODAL.CURRENT_CONTACT_LABEL') }}
      </span>
      <div
        class="border border-n-strong h-[60px] gap-2 flex items-center rounded-xl p-3"
      >
        <Avatar
          :name="conversationContact.name || ''"
          :src="
            conversationContact.thumbnail ||
            conversationContact.avatar_url ||
            ''
          "
          :size="32"
          rounded-full
        />
        <div class="flex flex-col w-full min-w-0 gap-1 flex-1">
          <span class="text-sm leading-4 truncate text-n-slate-12">
            {{ conversationContact.name }}
          </span>
          <span
            v-if="conversationPhoneNumber"
            class="text-sm leading-4 truncate text-n-slate-11"
          >
            {{ conversationPhoneNumber }}
          </span>
          <router-link
            v-else
            :to="editContactPath"
            class="text-sm leading-4 truncate text-n-brand"
          >
            {{ t('CONVERSATION.SHARE_CONTACT.MODAL.EDIT_CONTACT') }}
          </router-link>
        </div>
        <Button
          v-if="conversationPhoneNumber"
          variant="ghost"
          size="xs"
          :disabled="isSharing"
          :label="t('CONVERSATION.SHARE_CONTACT.MODAL.QUICK_SHARE')"
          @click="onQuickShare"
        />
      </div>
    </div>

    <p
      v-if="showConversationShortcut"
      class="text-xs text-center text-n-slate-11"
    >
      {{ t('CONVERSATION.SHARE_CONTACT.MODAL.OR_SEARCH') }}
    </p>

    <ComboBox
      id="share-contact-picker"
      use-api-results
      :model-value="selectedContactId"
      :options="contactOptions"
      :empty-state="
        isSearching
          ? t('CONVERSATION.SHARE_CONTACT.MODAL.IS_SEARCHING')
          : t('CONVERSATION.SHARE_CONTACT.MODAL.EMPTY_STATE')
      "
      :search-placeholder="
        t('CONVERSATION.SHARE_CONTACT.MODAL.SEARCH_PLACEHOLDER')
      "
      :placeholder="t('CONVERSATION.SHARE_CONTACT.MODAL.PLACEHOLDER')"
      class="[&>div>button]:bg-n-alpha-black2"
      @update:model-value="onSelect"
      @search="onSearch"
    />
  </div>
</template>
