<script setup>
import { useI18n } from 'vue-i18n';
import { getI18nKey } from 'dashboard/routes/dashboard/settings/helper/settingsHelper';
import { hasOverlappingConversationScope } from 'dashboard/helper/customRoleConversationScope';

import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'next/icon/Icon.vue';
import { BaseTableRow, BaseTableCell } from 'dashboard/components-next/table';

defineProps({
  roles: {
    type: Array,
    required: true,
  },
  loading: {
    type: Object,
    default: () => ({}),
  },
});

const emit = defineEmits(['edit', 'delete']);

const { t } = useI18n();

const getFormattedPermissions = role => {
  return role.permissions
    .map(event => t(getI18nKey('CUSTOM_ROLE.PERMISSIONS', event)))
    .join(', ');
};
</script>

<template>
  <BaseTableRow
    v-for="customRole in roles"
    :key="customRole.id"
    :item="customRole"
  >
    <template #default>
      <BaseTableCell>
        <span class="text-body-main text-n-slate-12 truncate block">
          {{ customRole.name }}
        </span>
      </BaseTableCell>

      <BaseTableCell>
        <span class="text-body-main text-n-slate-11 truncate block">
          {{ customRole.description }}
        </span>
      </BaseTableCell>

      <BaseTableCell>
        <div class="flex items-start gap-2 min-w-0">
          <span class="text-body-main text-n-slate-11 block min-w-0">
            {{ getFormattedPermissions(customRole) }}
          </span>
          <span
            v-if="hasOverlappingConversationScope(customRole.permissions)"
            v-tooltip.top="$t('CUSTOM_ROLE.LIST.SCOPE_OVERLAP_WARNING')"
            class="shrink-0 text-n-amber-11"
          >
            <Icon icon="i-lucide-alert-triangle" class="size-4" />
          </span>
        </div>
      </BaseTableCell>

      <BaseTableCell align="end" class="w-24">
        <div class="flex gap-3 justify-end flex-shrink-0">
          <Button
            v-tooltip.top="$t('CUSTOM_ROLE.EDIT.BUTTON_TEXT')"
            icon="i-woot-edit-pen"
            slate
            sm
            @click="emit('edit', customRole)"
          />
          <Button
            v-tooltip.top="$t('CUSTOM_ROLE.DELETE.BUTTON_TEXT')"
            icon="i-woot-bin"
            slate
            sm
            class="hover:enabled:text-n-ruby-11 hover:enabled:bg-n-ruby-2"
            :is-loading="loading[customRole.id]"
            @click="emit('delete', customRole)"
          />
        </div>
      </BaseTableCell>
    </template>
  </BaseTableRow>
</template>
