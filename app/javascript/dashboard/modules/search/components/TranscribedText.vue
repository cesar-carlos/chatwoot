<script setup>
import { computed } from 'vue';
import { useMessageFormatter } from 'shared/composables/useMessageFormatter';
import { useExpandableContent } from 'shared/composables/useExpandableContent';

const props = defineProps({
  text: {
    type: String,
    default: '',
  },
  searchTerm: {
    type: String,
    default: '',
  },
});

const { highlightContent } = useMessageFormatter();

const { contentElement, showReadMore, showReadLess, toggleExpanded } =
  useExpandableContent({ useResizeObserverForCheck: true });

const escapeHtml = html => {
  const wrapper = document.createElement('p');
  wrapper.textContent = html;
  return wrapper.textContent;
};

const displayText = computed(() => {
  const content = props.text || '';
  if (!props.searchTerm?.trim()) return content;

  return highlightContent(
    escapeHtml(content),
    props.searchTerm,
    'searchkey--highlight'
  );
});

const isHighlighted = computed(() => Boolean(props.searchTerm?.trim()));
</script>

<template>
  <span class="py-2 text-xs font-medium">
    {{ $t('SEARCH.TRANSCRIPT') }}
  </span>
  <div
    class="text-n-slate-11 pt-1 text-sm rounded-lg w-full break-words grid items-center"
    :class="showReadMore ? 'grid-cols-[1fr_auto]' : 'grid-cols-1'"
  >
    <div
      ref="contentElement"
      class="min-w-0"
      :class="{ 'overflow-hidden line-clamp-1': showReadMore }"
    >
      <span
        v-if="isHighlighted"
        v-dompurify-html="displayText"
        class="[&_.searchkey--highlight]:text-n-slate-12 [&_.searchkey--highlight]:font-semibold"
      />
      <template v-else>{{ text }}</template>
      <button
        v-if="showReadLess"
        class="text-sm text-n-slate-11 underline cursor-pointer bg-transparent border-0 p-0 hover:text-n-slate-12 font-medium ltr:ml-0.5 rtl:mr-0.5"
        @click.prevent.stop="toggleExpanded(false)"
      >
        {{ $t('SEARCH.READ_LESS') }}
      </button>
    </div>
    <button
      v-if="showReadMore"
      class="text-sm text-n-slate-11 underline cursor-pointer bg-transparent border-0 p-0 hover:text-n-slate-12 font-medium justify-self-end ltr:ml-0.5 rtl:mr-0.5"
      @click.prevent.stop="toggleExpanded(true)"
    >
      {{ $t('SEARCH.READ_MORE') }}
    </button>
  </div>
</template>
