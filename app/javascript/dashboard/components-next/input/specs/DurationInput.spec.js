import { defineComponent, ref } from 'vue';
import { mount } from '@vue/test-utils';
import DurationInput from '../DurationInput.vue';

const mountDurationInput = ({
  initialValue = null,
  initialUnit = 'minutes',
  storedUnit = 'minutes',
  units = ['minutes', 'hours', 'days'],
  min = 10,
  max = 100,
} = {}) => {
  const TestHost = defineComponent({
    components: { DurationInput },
    setup() {
      const duration = ref(initialValue);
      const unit = ref(initialUnit);
      const submittedDuration = ref(null);

      const handleSubmit = () => {
        submittedDuration.value = duration.value;
      };

      return {
        duration,
        unit,
        submittedDuration,
        handleSubmit,
        storedUnit,
        units,
        min,
        max,
      };
    },
    template: `
      <form @submit.prevent="handleSubmit">
        <DurationInput
          v-model="duration"
          v-model:unit="unit"
          :stored-unit="storedUnit"
          :units="units"
          :min="min"
          :max="max"
        />
        <output data-testid="duration">{{ duration }}</output>
        <output data-testid="submitted-duration">
          {{ submittedDuration }}
        </output>
      </form>
    `,
  });

  return mount(TestHost);
};

describe('DurationInput', () => {
  it('allows a multi-digit value to be typed before enforcing the minimum', async () => {
    const wrapper = mountDurationInput();
    const input = wrapper.get('input');

    await input.setValue('4');
    expect(input.element.value).toBe('4');

    await input.setValue(`${input.element.value}5`);
    expect(input.element.value).toBe('45');
    expect(wrapper.get('[data-testid="duration"]').text()).toBe('45');
  });

  it('normalizes values to the configured range on blur', async () => {
    const wrapper = mountDurationInput();
    const input = wrapper.get('input');

    await input.setValue('4');
    await input.trigger('blur');
    expect(input.element.value).toBe('10');

    await input.setValue('125');
    await input.trigger('blur');
    expect(input.element.value).toBe('100');
  });

  it('keeps minutes, hours, and days when no unit list is passed', () => {
    const wrapper = mountDurationInput();

    expect(
      wrapper.findAll('option').map(option => option.element.value)
    ).toEqual(['minutes', 'hours', 'days']);
  });

  it('stores seconds while still converting whole minutes', async () => {
    const wrapper = mountDurationInput({
      storedUnit: 'seconds',
      units: ['seconds', 'minutes', 'hours', 'days'],
      min: 0,
      max: Infinity,
    });

    expect(
      wrapper.findAll('option').map(option => option.element.value)
    ).toEqual(['seconds', 'minutes', 'hours', 'days']);

    await wrapper.get('input').setValue('2');
    expect(wrapper.get('[data-testid="duration"]').text()).toBe('120');
  });

  it('normalizes the value before Enter submits the form', async () => {
    const wrapper = mountDurationInput();
    const input = wrapper.get('input');

    await input.setValue('125');
    await input.trigger('keydown', { key: 'Enter' });
    await wrapper.get('form').trigger('submit');

    expect(wrapper.get('[data-testid="submitted-duration"]').text()).toBe(
      '100'
    );
  });
});
