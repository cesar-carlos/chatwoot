<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useDebounceFn } from '@vueuse/core';
import { useStore } from 'dashboard/composables/store';
import ContactAPI from 'dashboard/api/contacts';
import { createContactSearcher } from 'dashboard/components-next/NewConversation/helpers/composeConversationHelper';
import SingleSelect from 'dashboard/components-next/filter/inputs/SingleSelect.vue';
import { INBOX_TYPES } from 'dashboard/helper/inbox';

const SUPPORTED_INBOX_TYPES = [
  INBOX_TYPES.WHATSAPP,
  INBOX_TYPES.WAVOIP,
  INBOX_TYPES.TWILIO,
  INBOX_TYPES.SMS,
  INBOX_TYPES.EMAIL,
  INBOX_TYPES.API,
  INBOX_TYPES.WEB,
];

const props = defineProps({
  actionParams: {
    type: Array,
    default: () => [null, null, ''],
  },
});

const emit = defineEmits(['update:actionParams']);

const store = useStore();
const searchContacts = createContactSearcher();

const contactOptions = ref([]);
const isSearchingContacts = ref(false);
const selectedContact = ref(null);

const TEMPLATE_VARIABLES = [
  '{{conversation.display_id}}',
  '{{conversation.id}}',
  '{{contact.name}}',
  '{{contact.email}}',
  '{{contact.phone}}',
  '{{inbox.name}}',
  '{{rule.name}}',
];

const inboxOptions = computed(() =>
  (store.getters['inboxes/getInboxes'] || [])
    .filter(inbox => SUPPORTED_INBOX_TYPES.includes(inbox.channel_type))
    .map(inbox => ({
      id: inbox.id,
      name: inbox.name,
    }))
);

const selectedInbox = computed({
  get() {
    const inboxId = props.actionParams?.[0];
    if (!inboxId) return null;
    return (
      inboxOptions.value.find(inbox => inbox.id === Number(inboxId)) || null
    );
  },
  set(value) {
    emitParams(value?.id ?? null, props.actionParams?.[1], props.actionParams?.[2]);
  },
});

const message = computed({
  get: () => props.actionParams?.[2] || '',
  set: value => {
    emitParams(props.actionParams?.[0], props.actionParams?.[1], value);
  },
});

const contactSelectModel = computed({
  get: () => selectedContact.value,
  set: value => {
    selectedContact.value = value;
    emitParams(props.actionParams?.[0], value?.id ?? null, props.actionParams?.[2]);
  },
});

const emitParams = (inboxId, contactId, messageValue) => {
  emit('update:actionParams', [
    inboxId ?? null,
    contactId ?? null,
    messageValue ?? '',
  ]);
};

const formatContactLabel = contact => {
  const name = contact.name || contact.email || contact.phoneNumber || `#${contact.id}`;
  const detail = contact.email || contact.phoneNumber;
  if (detail && contact.name) return `${name} (${detail})`;
  return name;
};

const loadSelectedContact = async contactId => {
  if (!contactId) {
    selectedContact.value = null;
    return;
  }

  const id = Number(contactId);
  if (selectedContact.value?.id === id) return;

  try {
    const { data } = await ContactAPI.show(id);
    const payload = data?.payload || data;
    if (!payload?.id) return;

    selectedContact.value = {
      id: payload.id,
      name: formatContactLabel({
        id: payload.id,
        name: payload.name,
        email: payload.email,
        phoneNumber: payload.phone_number,
      }),
    };
  } catch {
    selectedContact.value = { id, name: `#${id}` };
  }
};

const runContactSearch = async query => {
  const trimmed = query?.trim() || '';
  if (!trimmed) {
    contactOptions.value = selectedContact.value ? [selectedContact.value] : [];
    isSearchingContacts.value = false;
    return;
  }

  isSearchingContacts.value = true;
  try {
    const results = await searchContacts(trimmed, { reachableOnly: false });
    if (results === null) return;

    contactOptions.value = (results || []).map(contact => ({
      id: contact.id,
      name: formatContactLabel(contact),
    }));
  } catch {
    contactOptions.value = [];
  } finally {
    isSearchingContacts.value = false;
  }
};

const debouncedContactSearch = useDebounceFn(runContactSearch, 300);

const onContactSearch = query => {
  isSearchingContacts.value = !!query?.trim();
  debouncedContactSearch(query);
};

watch(
  () => props.actionParams?.[1],
  contactId => {
    loadSelectedContact(contactId);
  },
  { immediate: true }
);

onMounted(() => {
  store.dispatch('inboxes/get');
});
</script>

<template>
  <div class="flex flex-col gap-3 pl-1">
    <div class="flex flex-col gap-1.5">
      <span class="text-sm font-medium text-n-slate-12">
        {{ $t('CONVERSATION_RULES.FORM.CONTACT_MESSAGE.INBOX_LABEL') }}
      </span>
      <SingleSelect
        v-model="selectedInbox"
        :options="inboxOptions"
        :placeholder="
          $t('CONVERSATION_RULES.FORM.CONTACT_MESSAGE.INBOX_PLACEHOLDER')
        "
      />
    </div>

    <div class="flex flex-col gap-1.5">
      <span class="text-sm font-medium text-n-slate-12">
        {{ $t('CONVERSATION_RULES.FORM.CONTACT_MESSAGE.CONTACT_LABEL') }}
      </span>
      <SingleSelect
        v-model="contactSelectModel"
        async-search
        :options="contactOptions"
        :is-searching="isSearchingContacts"
        :placeholder="
          $t('CONVERSATION_RULES.FORM.CONTACT_MESSAGE.CONTACT_PLACEHOLDER')
        "
        :search-placeholder="
          $t('CONVERSATION_RULES.FORM.CONTACT_MESSAGE.CONTACT_PLACEHOLDER')
        "
        @search="onContactSearch"
      />
    </div>

    <div class="flex flex-col gap-1.5">
      <span class="text-sm font-medium text-n-slate-12">
        {{ $t('CONVERSATION_RULES.FORM.CONTACT_MESSAGE.MESSAGE_LABEL') }}
      </span>
      <textarea
        v-model="message"
        rows="4"
        class="w-full rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2 text-sm text-n-slate-12 placeholder:text-n-slate-10"
        :placeholder="
          $t('CONVERSATION_RULES.FORM.CONTACT_MESSAGE.MESSAGE_PLACEHOLDER')
        "
      />
      <p class="text-xs text-n-slate-11">
        {{ $t('CONVERSATION_RULES.FORM.CONTACT_MESSAGE.VARIABLES_HINT') }}:
        {{ TEMPLATE_VARIABLES.join(', ') }}
      </p>
    </div>
  </div>
</template>
