<script setup>
import { ref, watch } from 'vue';
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
  isUpdating: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['updateGroqToken']);

const { t } = useI18n();
const tokenValue = ref(props.groqToken);

watch(
  () => props.groqToken,
  newVal => {
    tokenValue.value = newVal;
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
    <WithLabel
      :label="t('PROFILE_SETTINGS.FORM.GROQ_TOKEN.LABEL')"
      :help-text="t('PROFILE_SETTINGS.FORM.GROQ_TOKEN.HELP_TEXT')"
    >
      <NextInput
        v-model="tokenValue"
        type="password"
        class="w-full"
        :placeholder="t('PROFILE_SETTINGS.FORM.GROQ_TOKEN.PLACEHOLDER')"
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
