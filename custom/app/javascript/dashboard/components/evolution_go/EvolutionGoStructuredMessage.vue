<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import BaseBubble from 'next/message/bubbles/Base.vue';
import { useMessageContext } from 'dashboard/components-next/message/provider';
import { CONTENT_TYPES } from 'dashboard/components-next/message/constants';

const { content, contentAttributes, contentType } = useMessageContext();
const { t } = useI18n();

const items = computed(() => {
  const value = contentAttributes.value?.items;
  return Array.isArray(value) ? value : [];
});

const isArticle = computed(() => contentType.value === CONTENT_TYPES.ARTICLE);

function mediaUrl(item) {
  return item?.media_url || item?.mediaUrl || '';
}

function actionKey(action, index) {
  return (
    action?.payload || action?.uri || `${action?.text || 'action'}-${index}`
  );
}
</script>

<template>
  <BaseBubble>
    <div class="flex flex-col gap-3">
      <p
        v-if="content"
        class="text-sm text-n-slate-12 whitespace-pre-wrap break-words"
      >
        {{ content }}
      </p>
      <p v-if="!items.length" class="text-sm text-n-slate-11">
        {{ t('CONVERSATION.EVOLUTION_GO_STRUCTURED.EMPTY') }}
      </p>
      <article
        v-for="(item, index) in items"
        :key="item.title || item.link || index"
        class="flex flex-col gap-1"
      >
        <img
          v-if="mediaUrl(item)"
          :src="mediaUrl(item)"
          alt=""
          class="max-h-40 w-full rounded-lg object-cover"
        />
        <h4 v-if="item.title" class="text-sm font-medium text-n-slate-12">
          {{ item.title }}
        </h4>
        <p
          v-if="item.description"
          class="text-sm text-n-slate-11 whitespace-pre-wrap break-words"
        >
          {{ item.description }}
        </p>
        <a
          v-if="isArticle && item.link"
          :href="item.link"
          target="_blank"
          rel="noopener noreferrer"
          class="text-sm text-n-blue-11 break-all underline"
        >
          {{ item.link }}
        </a>
        <ul v-if="item.actions?.length" class="flex flex-col gap-1">
          <li
            v-for="(action, actionIndex) in item.actions"
            :key="actionKey(action, actionIndex)"
            class="text-sm text-n-slate-12"
          >
            <a
              v-if="action.type === 'link' && action.uri"
              :href="action.uri"
              target="_blank"
              rel="noopener noreferrer"
              class="text-n-blue-11 underline"
            >
              {{ action.text }}
            </a>
            <span v-else>{{ action.text }}</span>
          </li>
        </ul>
      </article>
    </div>
  </BaseBubble>
</template>
