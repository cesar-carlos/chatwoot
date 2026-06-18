<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import { useAlert } from 'dashboard/composables';
import NextButton from 'dashboard/components-next/button/Button.vue';
import WithLabel from 'v3/components/Form/WithLabel.vue';
import NextInput from 'next/input/Input.vue';

const props = defineProps({
  groqToken: {
    type: String,
    default: '',
  },
  hasGroqToken: {
    type: Boolean,
    default: false,
  },
  isUpdating: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['updateGroqToken']);

const { t } = useI18n();
const tokenValue = ref(props.groqToken);

const isConfigured = computed(() => props.hasGroqToken && !tokenValue.value);

const inputPlaceholder = computed(() => {
  if (isConfigured.value) {
    return t('PROFILE_SETTINGS.FORM.GROQ_TOKEN.CONFIGURED_PLACEHOLDER');
  }

  return t('PROFILE_SETTINGS.FORM.GROQ_TOKEN.PLACEHOLDER');
});

watch(
  () => props.groqToken,
  newVal => {
    tokenValue.value = newVal;
  }
);

watch(
  () => props.hasGroqToken,
  hasToken => {
    if (hasToken && !props.groqToken) {
      tokenValue.value = '';
    }
  }
);

const updateToken = () => {
  emit('updateGroqToken', tokenValue.value);
};

const copyToken = async () => {
  if (!tokenValue.value) {
    return;
  }
  try {
    await copyTextToClipboard(tokenValue.value);
    useAlert(t('PROFILE_SETTINGS.FORM.GROQ_TOKEN.COPY_SUCCESS'));
  } catch (error) {
    useAlert(t('PROFILE_SETTINGS.FORM.GROQ_TOKEN.COPY_ERROR'));
  }
};
</script>

<template>
  <form class="flex flex-col gap-4" @submit.prevent="updateToken">
    <div
      v-if="isConfigured"
      class="flex items-center gap-2 text-sm text-n-teal-11"
    >
      <span class="i-lucide-circle-check size-4 shrink-0" />
      <span>{{ t('PROFILE_SETTINGS.FORM.GROQ_TOKEN.CONFIGURED_STATUS') }}</span>
    </div>
    <WithLabel
      :label="t('PROFILE_SETTINGS.FORM.GROQ_TOKEN.LABEL')"
      :help-text="
        isConfigured
          ? t('PROFILE_SETTINGS.FORM.GROQ_TOKEN.CONFIGURED_HELP_TEXT')
          : t('PROFILE_SETTINGS.FORM.GROQ_TOKEN.HELP_TEXT')
      "
    >
      <NextInput
        v-model="tokenValue"
        type="password"
        class="w-full"
        :placeholder="inputPlaceholder"
      />
    </WithLabel>
    <div class="flex items-center gap-2 text-sm text-n-slate-11">
      <span>{{ t('PROFILE_SETTINGS.FORM.GROQ_TOKEN.GET_TOKEN_TEXT') }}</span>
      <a
        href="https://console.groq.com"
        target="_blank"
        rel="noopener noreferrer"
        class="text-n-blue-11 hover:text-n-blue-10 underline"
      >
        {{ t('PROFILE_SETTINGS.FORM.GROQ_TOKEN.CONSOLE_LINK_TEXT') }}
      </a>
    </div>
    <div class="flex items-center gap-2">
      <NextButton
        type="submit"
        blue
        :disabled="isUpdating"
        :loading="isUpdating"
      >
        {{ t('PROFILE_SETTINGS.FORM.GROQ_TOKEN.SAVE_BTN') }}
      </NextButton>
      <NextButton
        type="button"
        slate
        outline
        icon="i-lucide-copy"
        :disabled="!tokenValue || isUpdating"
        @click="copyToken"
      >
        {{ t('PROFILE_SETTINGS.FORM.GROQ_TOKEN.COPY') }}
      </NextButton>
    </div>
  </form>
</template>
