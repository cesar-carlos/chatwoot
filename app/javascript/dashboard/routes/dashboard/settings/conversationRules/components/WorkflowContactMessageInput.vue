<script setup>
import { computed, nextTick, onMounted, ref, watch } from 'vue';
import { useDebounceFn } from '@vueuse/core';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
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

const PHONE_REQUIRED_TYPES = [
  INBOX_TYPES.WHATSAPP,
  INBOX_TYPES.WAVOIP,
  INBOX_TYPES.TWILIO,
  INBOX_TYPES.SMS,
];

const WHATSAPP_WARN_TYPES = [INBOX_TYPES.WHATSAPP, INBOX_TYPES.WAVOIP];

const TEMPLATE_VARIABLES = [
  'conversation.display_id',
  'conversation.id',
  'contact.name',
  'contact.email',
  'contact.phone_number',
  'inbox.name',
  'account.name',
  'rule.name',
];

const SAMPLE_VALUES = {
  'conversation.display_id': '1234',
  'conversation.id': '1234',
  'contact.name': 'João',
  'contact.email': 'joao@example.com',
  'contact.phone_number': '+5511999999999',
  'contact.phone': '+5511999999999',
  'inbox.name': 'WhatsApp',
  'account.name': 'Acme',
  'rule.name': 'Cliente sem resposta 15 min',
};

const props = defineProps({
  actionParams: {
    type: Array,
    default: () => [null, null, ''],
  },
});

const emit = defineEmits(['update:actionParams']);

const { t } = useI18n();
const store = useStore();
const { accountId } = useAccount();
const searchContacts = createContactSearcher();

const rootEl = ref(null);
const messageInputRef = ref(null);
const contactOptions = ref([]);
const isSearchingContacts = ref(false);
const selectedContact = ref(null);
const contactMeta = ref({ hasPhone: false, hasEmail: false });
const favorites = ref([]);
const channelError = ref('');

const favoritesStorageKey = computed(
  () => `cw_favorite_contacts_${accountId.value}`
);

const loadFavorites = () => {
  try {
    const raw = localStorage.getItem(favoritesStorageKey.value);
    favorites.value = raw ? JSON.parse(raw) : [];
  } catch {
    favorites.value = [];
  }
};

const persistFavorites = () => {
  localStorage.setItem(
    favoritesStorageKey.value,
    JSON.stringify(favorites.value.slice(0, 8))
  );
};

const inboxRecords = computed(() =>
  (store.getters['inboxes/getInboxes'] || []).filter(inbox =>
    SUPPORTED_INBOX_TYPES.includes(inbox.channel_type)
  )
);

const inboxOptions = computed(() =>
  inboxRecords.value.map(inbox => ({
    id: inbox.id,
    name: inbox.name,
  }))
);

const selectedInboxRecord = computed(() => {
  const inboxId = Number(props.actionParams?.[0]);
  if (!inboxId) return null;
  return inboxRecords.value.find(inbox => inbox.id === inboxId) || null;
});

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

// SingleSelect only emits { id, name }; recover phone/email from search options or API.
const contactFieldsFrom = contact => {
  if (!contact) return { phone_number: '', email: '' };
  const fromOptions = contactOptions.value.find(item => item.id === contact.id);
  return {
    phone_number:
      contact.phone_number ||
      contact.phoneNumber ||
      fromOptions?.phone_number ||
      '',
    email: contact.email || fromOptions?.email || '',
  };
};

const applyResolvedContact = contact => {
  selectedContact.value = contact;
  emitContact(contact);
  validateChannelMatch();
};

const resolveSelectedContact = async contact => {
  if (!contact?.id) {
    applyResolvedContact(null);
    return;
  }

  const { phone_number, email } = contactFieldsFrom(contact);
  if (phone_number || email) {
    applyResolvedContact({
      id: contact.id,
      name: contact.name,
      email,
      phone_number,
    });
    return;
  }

  await fetchContactById(contact.id, contact.name);
};

const contactSelectModel = computed({
  get: () => selectedContact.value,
  set: value => {
    resolveSelectedContact(value);
  },
});

const showWhatsappWarning = computed(() =>
  WHATSAPP_WARN_TYPES.includes(selectedInboxRecord.value?.channel_type)
);

const isFavoriteSelected = computed(() => {
  const id = selectedContact.value?.id;
  if (!id) return false;
  return favorites.value.some(item => item.id === id);
});

const messagePreview = computed(() => {
  const template = message.value || '';
  if (!template.trim()) return '';
  return template.replace(/\{\{\s*([\w.]+)\s*\}\}/g, (match, key) => {
    return SAMPLE_VALUES[key] ?? match;
  });
});

const templateOptions = computed(() => [
  {
    key: 'attention',
    label: t('CONVERSATION_RULES.FORM.CONTACT_MESSAGE.TEMPLATES.ATTENTION_LABEL'),
    body: t('CONVERSATION_RULES.FORM.CONTACT_MESSAGE.TEMPLATES.ATTENTION_BODY'),
  },
  {
    key: 'escalation',
    label: t(
      'CONVERSATION_RULES.FORM.CONTACT_MESSAGE.TEMPLATES.ESCALATION_LABEL'
    ),
    body: t('CONVERSATION_RULES.FORM.CONTACT_MESSAGE.TEMPLATES.ESCALATION_BODY'),
  },
  {
    key: 'reminder',
    label: t('CONVERSATION_RULES.FORM.CONTACT_MESSAGE.TEMPLATES.REMINDER_LABEL'),
    body: t('CONVERSATION_RULES.FORM.CONTACT_MESSAGE.TEMPLATES.REMINDER_BODY'),
  },
]);

const emitParams = (inboxId, contactValue, messageValue) => {
  emit('update:actionParams', [
    inboxId ?? null,
    contactValue ?? null,
    messageValue ?? '',
  ]);
};

const emitContact = contact => {
  if (!contact?.id) {
    contactMeta.value = { hasPhone: false, hasEmail: false };
    if (props.actionParams?.[1] != null) {
      emitParams(props.actionParams?.[0], null, props.actionParams?.[2]);
    }
    return;
  }

  const payload = {
    id: contact.id,
    name: contact.name,
    phone_number: contact.phone_number || contact.phoneNumber || '',
    email: contact.email || '',
  };
  contactMeta.value = {
    hasPhone: !!payload.phone_number,
    hasEmail: !!payload.email,
  };

  const current = props.actionParams?.[1];
  if (
    current &&
    typeof current === 'object' &&
    Number(current.id) === Number(payload.id) &&
    (current.phone_number || current.phoneNumber || '') === payload.phone_number &&
    (current.email || '') === payload.email
  ) {
    return;
  }

  emitParams(props.actionParams?.[0], payload, props.actionParams?.[2]);
};

const formatContactLabel = contact => {
  const name =
    contact.name || contact.email || contact.phoneNumber || `#${contact.id}`;
  const detail = contact.email || contact.phoneNumber;
  if (detail && contact.name) return `${name} (${detail})`;
  return name;
};

const validateChannelMatch = () => {
  const channel = selectedInboxRecord.value?.channel_type;
  if (!channel || !selectedContact.value?.id) {
    channelError.value = '';
    return true;
  }

  if (PHONE_REQUIRED_TYPES.includes(channel) && !contactMeta.value.hasPhone) {
    channelError.value = t(
      'CONVERSATION_RULES.VALIDATION.CONTACT_CHANNEL_MISMATCH'
    );
    return false;
  }

  if (channel === INBOX_TYPES.EMAIL && !contactMeta.value.hasEmail) {
    channelError.value = t(
      'CONVERSATION_RULES.VALIDATION.CONTACT_CHANNEL_MISMATCH'
    );
    return false;
  }

  channelError.value = '';
  return true;
};

const fetchContactById = async (contactId, fallbackName) => {
  const id = Number(contactId);
  if (!id) return;

  if (
    selectedContact.value?.id === id &&
    (contactMeta.value.hasPhone || contactMeta.value.hasEmail)
  ) {
    return;
  }

  try {
    const { data } = await ContactAPI.show(id);
    const payload = data?.payload || data;
    if (!payload?.id) return;

    applyResolvedContact({
      id: payload.id,
      name: formatContactLabel({
        id: payload.id,
        name: payload.name,
        email: payload.email,
        phoneNumber: payload.phone_number,
      }),
      email: payload.email || '',
      phone_number: payload.phone_number || '',
    });
  } catch {
    applyResolvedContact({
      id,
      name: fallbackName || `#${id}`,
      email: '',
      phone_number: '',
    });
  }
};

const loadSelectedContact = async contactValue => {
  if (!contactValue) {
    selectedContact.value = null;
    contactMeta.value = { hasPhone: false, hasEmail: false };
    channelError.value = '';
    return;
  }

  if (typeof contactValue === 'object' && contactValue.id) {
    const { phone_number, email } = contactFieldsFrom(contactValue);
    if (phone_number || email) {
      applyResolvedContact({
        id: contactValue.id,
        name:
          contactValue.name ||
          formatContactLabel({
            id: contactValue.id,
            name: contactValue.name,
            email,
            phoneNumber: phone_number,
          }),
        email,
        phone_number,
      });
      return;
    }

    await fetchContactById(contactValue.id, contactValue.name);
    return;
  }

  await fetchContactById(contactValue);
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
      email: contact.email || '',
      phone_number: contact.phoneNumber || contact.phone_number || '',
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

const insertVariable = async key => {
  const token = `{{${key}}}`;
  const el = messageInputRef.value;
  const current = message.value || '';

  if (!el) {
    message.value = `${current}${token}`;
    return;
  }

  const start = el.selectionStart ?? current.length;
  const end = el.selectionEnd ?? current.length;
  const next = `${current.slice(0, start)}${token}${current.slice(end)}`;
  message.value = next;

  await nextTick();
  const caret = start + token.length;
  el.focus();
  el.setSelectionRange(caret, caret);
};

const applyTemplate = body => {
  message.value = body;
};

const toggleFavorite = () => {
  if (!selectedContact.value?.id) return;
  const id = selectedContact.value.id;
  const exists = favorites.value.find(item => item.id === id);
  if (exists) {
    favorites.value = favorites.value.filter(item => item.id !== id);
  } else {
    favorites.value = [
      {
        id,
        name: selectedContact.value.name,
        email: selectedContact.value.email || '',
        phone_number: selectedContact.value.phone_number || '',
      },
      ...favorites.value.filter(item => item.id !== id),
    ].slice(0, 8);
  }
  persistFavorites();
};

const selectFavorite = favorite => {
  resolveSelectedContact({
    id: favorite.id,
    name: favorite.name,
    email: favorite.email || '',
    phone_number: favorite.phone_number || '',
  });
};

watch(
  () => props.actionParams?.[1],
  contactValue => {
    loadSelectedContact(contactValue);
  },
  { immediate: true }
);

watch(
  () => [props.actionParams?.[0], selectedContact.value?.id, contactMeta.value],
  () => validateChannelMatch(),
  { deep: true }
);

onMounted(() => {
  store.dispatch('inboxes/get');
  loadFavorites();
});

const formatVariableChip = key => `{{${key}}}`;

defineExpose({
  rootEl,
  validateChannelMatch,
  channelError,
});
</script>

<template>
  <div ref="rootEl" class="flex flex-col gap-3 pl-1" data-contact-message-block>
    <div class="flex flex-col gap-1.5">
      <span class="text-sm font-medium text-n-slate-12">
        {{ $t('CONVERSATION_RULES.FORM.CONTACT_MESSAGE.INBOX_LABEL') }}
      </span>
      <p
        v-if="!inboxOptions.length"
        class="text-sm text-n-amber-11 rounded-lg border border-n-amber-6 bg-n-amber-2 p-3"
      >
        {{ $t('CONVERSATION_RULES.FORM.CONTACT_MESSAGE.NO_SUPPORTED_INBOXES') }}
      </p>
      <SingleSelect
        v-else
        v-model="selectedInbox"
        :options="inboxOptions"
        :placeholder="
          $t('CONVERSATION_RULES.FORM.CONTACT_MESSAGE.INBOX_PLACEHOLDER')
        "
      />
      <p
        v-if="showWhatsappWarning"
        class="text-xs text-n-amber-11 rounded-lg border border-n-amber-6 bg-n-amber-2 p-2.5"
      >
        {{ $t('CONVERSATION_RULES.FORM.CONTACT_MESSAGE.WHATSAPP_WINDOW_WARNING') }}
      </p>
    </div>

    <div class="flex flex-col gap-1.5">
      <div class="flex items-center justify-between gap-2">
        <span class="text-sm font-medium text-n-slate-12">
          {{ $t('CONVERSATION_RULES.FORM.CONTACT_MESSAGE.CONTACT_LABEL') }}
        </span>
        <button
          v-if="selectedContact?.id"
          type="button"
          class="text-n-slate-11 hover:text-n-amber-11"
          :aria-label="
            $t('CONVERSATION_RULES.FORM.CONTACT_MESSAGE.FAVORITE_TOGGLE')
          "
          @click="toggleFavorite"
        >
          <span
            class="size-4"
            :class="
              isFavoriteSelected ? 'i-lucide-star-fill text-n-amber-11' : 'i-lucide-star'
            "
            aria-hidden="true"
          />
        </button>
      </div>
      <div v-if="favorites.length" class="flex flex-wrap gap-1.5">
        <button
          v-for="favorite in favorites"
          :key="favorite.id"
          type="button"
          class="text-xs px-2 py-1 rounded-md border border-n-weak text-n-slate-11 hover:bg-n-alpha-2"
          @click="selectFavorite(favorite)"
        >
          {{ favorite.name }}
        </button>
      </div>
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
      <p v-if="channelError" class="text-xs text-n-ruby-11">
        {{ channelError }}
      </p>
    </div>

    <div class="flex flex-col gap-1.5">
      <span class="text-sm font-medium text-n-slate-12">
        {{ $t('CONVERSATION_RULES.FORM.CONTACT_MESSAGE.MESSAGE_LABEL') }}
      </span>
      <div class="flex flex-wrap gap-1.5">
        <button
          v-for="option in templateOptions"
          :key="option.key"
          type="button"
          class="text-xs px-2 py-1 rounded-md border border-n-weak text-n-slate-11 hover:bg-n-alpha-2"
          @click="applyTemplate(option.body)"
        >
          {{ option.label }}
        </button>
      </div>
      <textarea
        ref="messageInputRef"
        v-model="message"
        rows="4"
        class="w-full rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2 text-sm text-n-slate-12 placeholder:text-n-slate-10"
        :placeholder="
          $t('CONVERSATION_RULES.FORM.CONTACT_MESSAGE.MESSAGE_PLACEHOLDER')
        "
      />
      <div class="flex flex-wrap gap-1.5">
        <button
          v-for="variable in TEMPLATE_VARIABLES"
          :key="variable"
          type="button"
          class="text-xs px-2 py-1 rounded-md bg-n-alpha-2 text-n-slate-12 hover:bg-n-alpha-3 font-mono"
          @click="insertVariable(variable)"
        >
          {{ formatVariableChip(variable) }}
        </button>
      </div>
      <p class="text-xs text-n-slate-11">
        {{ $t('CONVERSATION_RULES.FORM.CONTACT_MESSAGE.VARIABLES_HINT') }}
      </p>
      <div
        v-if="messagePreview"
        class="rounded-lg border border-n-weak bg-n-solid-1 p-2.5"
      >
        <p class="text-xs font-medium text-n-slate-11 mb-1">
          {{ $t('CONVERSATION_RULES.FORM.CONTACT_MESSAGE.PREVIEW_LABEL') }}
        </p>
        <p class="text-sm text-n-slate-12 whitespace-pre-wrap">
          {{ messagePreview }}
        </p>
      </div>
    </div>
  </div>
</template>
