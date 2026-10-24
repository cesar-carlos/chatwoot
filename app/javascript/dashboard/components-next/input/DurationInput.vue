<script setup>
import { computed, watch } from 'vue';
import Input from './Input.vue';
import { useI18n } from 'vue-i18n';
import { DURATION_UNITS } from './constants';

const props = defineProps({
  min: { type: Number, default: 0 },
  max: { type: Number, default: Infinity },
  disabled: { type: Boolean, default: false },
  units: {
    type: Array,
    default: () => [
      DURATION_UNITS.MINUTES,
      DURATION_UNITS.HOURS,
      DURATION_UNITS.DAYS,
    ],
  },
  storedUnit: {
    type: String,
    default: DURATION_UNITS.MINUTES,
  },
});

// FORK: convert through seconds so a caller can store seconds and still offer minutes, hours, and days.
const SECONDS_PER_UNIT = {
  [DURATION_UNITS.SECONDS]: 1,
  [DURATION_UNITS.MINUTES]: 60,
  [DURATION_UNITS.HOURS]: 60 * 60,
  [DURATION_UNITS.DAYS]: 24 * 60 * 60,
};

const { t } = useI18n();
const duration = defineModel('modelValue', { type: Number, default: null });
const unit = defineModel('unit', {
  type: String,
  default: DURATION_UNITS.MINUTES,
  validate(value) {
    return Object.values(DURATION_UNITS).includes(value);
  },
});

const secondsPer = unitName => SECONDS_PER_UNIT[unitName] || 0;

const toStored = displayValue => {
  const displaySeconds = secondsPer(unit.value);
  const storedSeconds = secondsPer(props.storedUnit);
  if (!displaySeconds || !storedSeconds) return 0;

  return Math.floor(
    (Math.floor(displayValue) * displaySeconds) / storedSeconds
  );
};

const toDisplay = storedValue => {
  const displaySeconds = secondsPer(unit.value);
  const storedSeconds = secondsPer(props.storedUnit);
  if (!displaySeconds || !storedSeconds) return 0;

  return Math.floor((storedValue * storedSeconds) / displaySeconds);
};

const transformedValue = computed({
  get() {
    if (duration.value == null) return null;
    return toDisplay(duration.value);
  },
  set(newValue) {
    if (newValue == null || newValue === '') {
      duration.value = null;
      return;
    }
    duration.value = toStored(newValue);
  },
});

const normalizeDuration = () => {
  if (duration.value == null) return;

  duration.value = Math.min(Math.max(duration.value, props.min), props.max);
};

// when unit is changed set the nearest value to that unit
// so if the minute is set to 900, and the user changes the unit to "days"
// the transformed value will show 0, but the real value will still be 900
// this might create some confusion, especially when saving
// this watcher fixes it by rounding the duration basically, to the nearest unit value
watch(unit, () => {
  if (duration.value == null) return;
  const adjustedValue = toStored(transformedValue.value);
  duration.value = Math.min(Math.max(adjustedValue, props.min), props.max);
});
</script>

<template>
  <Input
    v-model="transformedValue"
    type="number"
    autocomplete="off"
    :disabled="disabled"
    :placeholder="t('DURATION_INPUT.PLACEHOLDER')"
    class="flex-grow w-full disabled:"
    @blur="normalizeDuration"
    @keydown.enter="normalizeDuration"
  />
  <select
    v-model="unit"
    :disabled="disabled"
    class="mb-0 text-sm disabled:outline-n-weak disabled:opacity-40"
  >
    <option v-for="option in units" :key="option" :value="option">
      {{ t(`DURATION_INPUT.${option.toUpperCase()}`) }}
    </option>
  </select>
</template>
