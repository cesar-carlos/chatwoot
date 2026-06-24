<script setup>
import { computed, nextTick, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useWindowSize } from '@vueuse/core';
import { vOnClickOutside } from '@vueuse/components';

import Button from 'dashboard/components-next/button/Button.vue';
import ConversationMessageSearchView from './ConversationMessageSearchView.vue';
import { useConversationMessageSearchPanel } from 'dashboard/composables/fork/useConversationMessageSearchPanel';
import { useUISettings } from 'dashboard/composables/useUISettings';
import wootConstants from 'dashboard/constants/globals';

defineProps({
  currentChat: {
    required: true,
    type: Object,
  },
});

const { t } = useI18n();
const { close: closePanel, isOpen } = useConversationMessageSearchPanel();
const { uiSettings, updateUISettings } = useUISettings();
const { width: windowWidth } = useWindowSize();

const searchViewRef = ref(null);

const isSmallScreen = computed(
  () => windowWidth.value < wootConstants.SMALL_SCREEN_BREAKPOINT
);

const closeSearchPanel = () => {
  searchViewRef.value?.close();
  closePanel();
};

const closeOnOutsideClick = () => {
  if (isSmallScreen.value && uiSettings.value?.is_message_search_panel_open) {
    updateUISettings({
      is_message_search_panel_open: false,
      is_contact_sidebar_open: false,
      is_copilot_panel_open: false,
    });
    searchViewRef.value?.close();
  }
};

defineExpose({
  open: () => {
    searchViewRef.value?.prepareOpen();
  },
  close: closeSearchPanel,
});

watch(
  isOpen,
  async open => {
    if (!open) return;
    await nextTick();
    searchViewRef.value?.prepareOpen();
  },
  { immediate: true }
);
</script>

<template>
  <div
    v-on-click-outside="[
      () => closeOnOutsideClick(),
      {
        ignore: [
          'dialog.ProseMirror-prompt-backdrop',
          '[data-popover-content]',
          '[data-popover-backdrop]',
        ],
      },
    ]"
    class="bg-n-surface-2 h-full overflow-hidden flex flex-col fixed top-0 z-40 w-full max-w-sm transition-transform duration-300 ease-in-out ltr:right-0 rtl:left-0 md:static md:w-[320px] md:min-w-[320px] ltr:border-l rtl:border-r border-n-weak 2xl:min-w-[360px] 2xl:w-[360px] shadow-lg md:shadow-none"
    role="complementary"
    :aria-label="t('CONVERSATION.MESSAGE_SEARCH.PANEL_TITLE')"
  >
    <div
      class="flex items-center justify-between gap-2 px-4 py-3 border-b border-n-weak"
    >
      <div class="min-w-0">
        <h2 class="text-base font-medium text-n-slate-12 truncate">
          {{ t('CONVERSATION.MESSAGE_SEARCH.PANEL_TITLE') }}
        </h2>
        <p class="text-xs text-n-slate-11 truncate">
          {{ t('CONVERSATION.MESSAGE_SEARCH.PANEL_DESCRIPTION') }}
        </p>
      </div>
      <Button
        v-tooltip.left="$t('CONVERSATION.MESSAGE_SEARCH.PANEL_CLOSE')"
        ghost
        slate
        sm
        icon="i-lucide-x"
        class="flex-shrink-0"
        @click="closeSearchPanel"
      />
    </div>

    <div class="flex flex-1 min-h-0 flex-col overflow-hidden p-4">
      <ConversationMessageSearchView
        v-if="currentChat?.id"
        ref="searchViewRef"
        :conversation-id="currentChat.id"
        :on-close="closePanel"
      />
    </div>
  </div>
</template>
