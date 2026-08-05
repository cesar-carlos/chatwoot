<script>
import MultiSelect from 'dashboard/components-next/filter/inputs/MultiSelect.vue';
// FORK: Liquid variable chips for send_email_to_team message body
import AutomationMessageVariables from 'dashboard/routes/dashboard/settings/automation/components/AutomationMessageVariables.vue';

export default {
  components: {
    MultiSelect,
    AutomationMessageVariables,
  },
  props: {
    teams: { type: Array, required: true },
    modelValue: { type: Object, required: true },
    dropdownMaxHeight: { type: String, default: 'max-h-80' },
  },
  emits: ['update:modelValue'],
  data() {
    return {
      selectedTeams: [],
      message: '',
    };
  },
  mounted() {
    const { team_ids: teamIds, message } = this.modelValue || {};
    this.selectedTeams = teamIds || [];
    this.message = message || '';
  },
  methods: {
    updateValue() {
      this.$emit('update:modelValue', {
        team_ids: this.selectedTeams.map(team => team.id),
        message: this.message,
      });
    },
    // FORK: insert at native textarea cursor when possible
    insertMessageVariable(token) {
      const el = this.$refs.teamMessageInput;
      if (el && typeof el.selectionStart === 'number') {
        const start = el.selectionStart;
        const end = el.selectionEnd;
        const before = this.message.slice(0, start);
        const after = this.message.slice(end);
        const spacer = before && !/\s$/.test(before) ? ' ' : '';
        this.message = `${before}${spacer}${token}${after}`;
        this.updateValue();
        this.$nextTick(() => {
          const pos = start + spacer.length + token.length;
          el.focus();
          el.setSelectionRange(pos, pos);
        });
        return;
      }

      const spacer = this.message && !/\s$/.test(this.message) ? ' ' : '';
      this.message = `${this.message || ''}${spacer}${token}`;
      this.updateValue();
    },
  },
};
</script>

<template>
  <div class="flex flex-col gap-2">
    <MultiSelect
      v-model="selectedTeams"
      :options="teams"
      :dropdown-max-height="dropdownMaxHeight"
      @update:model-value="updateValue"
    />
    <textarea
      ref="teamMessageInput"
      v-model="message"
      class="mb-0 !text-sm"
      rows="4"
      :placeholder="$t('AUTOMATION.ACTION.TEAM_MESSAGE_INPUT_PLACEHOLDER')"
      @input="updateValue"
    />
    <!-- FORK: Liquid chips for team email body -->
    <AutomationMessageVariables
      :message="message || ''"
      executed-by-kind="rule"
      @insert-variable="insertMessageVariable"
    />
  </div>
</template>
