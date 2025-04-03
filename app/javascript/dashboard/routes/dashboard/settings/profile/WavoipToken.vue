<script setup>
import { ref, computed, watch } from 'vue';
import FormButton from 'v3/components/Form/Button.vue';

const props = defineProps({
  value: {
    type: String,
    default: '',
  },
});

const emit = defineEmits(['onCopy', 'onSave']);
const inputType = ref('password');
const localValue = ref(props.value);

watch(
  () => props.value,
  newValue => {
    localValue.value = newValue;
  }
);

const toggleMasked = () => {
  inputType.value = inputType.value === 'password' ? 'text' : 'password';
};

const maskIcon = computed(() => {
  return inputType.value === 'password' ? 'eye-hide' : 'eye-show';
});

const onCopy = () => {
  emit('onCopy', props.value);
};

const onSave = () => {
  emit('onSave', localValue.value);
};
</script>

<template>
  <div class="flex flex-col gap-4">
    <div class="flex flex-row justify-between gap-4">
      <woot-input
        v-model="localValue"
        name="wavoip_token"
        class="flex-1 [&>input]:!py-1.5 ltr:[&>input]:!pr-9 ltr:[&>input]:!pl-3 rtl:[&>input]:!pl-9 rtl:[&>input]:!pr-3 focus:[&>input]:!border-slate-200 focus:[&>input]:dark:!border-slate-600 relative"
        :styles="{
          borderRadius: '12px',
          fontSize: '14px',
          marginBottom: '2px',
        }"
        :type="inputType"
        :placeholder="$t('PROFILE_SETTINGS.FORM.WAVOIP_TOKEN.PLACEHOLDER')"
      >
        <template #masked>
          <button
            class="absolute top-1.5 ltr:right-0.5 rtl:left-0.5"
            @click="toggleMasked"
          >
            <fluent-icon :icon="maskIcon" :size="16" />
          </button>
        </template>
      </woot-input>
      <FormButton
        type="submit"
        size="large"
        icon="text-copy"
        variant="outline"
        color-scheme="secondary"
        @click="onCopy"
      >
        {{ $t('COMPONENTS.CODE.COPY') }}
      </FormButton>
    </div>
    <div class="flex">
      <FormButton
        type="submit"
        size="large"
        icon="save"
        color-scheme="primary"
        @click="onSave"
      >
        {{ $t('PROFILE_SETTINGS.FORM.WAVOIP_TOKEN.SAVE_BUTTON') }}
      </FormButton>
    </div>
  </div>
</template>
