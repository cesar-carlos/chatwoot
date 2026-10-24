import { describe, expect, it, vi } from 'vitest';
import { shallowMount } from '@vue/test-utils';
import { ref } from 'vue';

const messageState = {
  content: ref('Offers'),
  contentType: ref('cards'),
  contentAttributes: ref({
    items: [
      {
        title: 'Day offer',
        description: 'Only today',
        media_url: 'https://cdn.example/offer.png',
        actions: [
          { text: 'More', type: 'link', uri: 'https://example.org/more' },
          { text: 'Buy', type: 'postback', payload: 'buy' },
        ],
      },
    ],
  }),
};

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

vi.mock('dashboard/components-next/message/provider', () => ({
  useMessageContext: () => messageState,
}));

import EvolutionGoStructuredMessage from '../EvolutionGoStructuredMessage.vue';

const mountBubble = () =>
  shallowMount(EvolutionGoStructuredMessage, {
    global: {
      stubs: {
        BaseBubble: { template: '<div><slot /></div>' },
      },
    },
  });

describe('EvolutionGoStructuredMessage', () => {
  it('shows the card title, description, media and actions', () => {
    messageState.content.value = 'Offers';
    messageState.contentType.value = 'cards';
    messageState.contentAttributes.value = {
      items: [
        {
          title: 'Day offer',
          description: 'Only today',
          media_url: 'https://cdn.example/offer.png',
          actions: [
            { text: 'More', type: 'link', uri: 'https://example.org/more' },
            { text: 'Buy', type: 'postback', payload: 'buy' },
          ],
        },
      ],
    };

    const wrapper = mountBubble();

    expect(wrapper.text()).toContain('Offers');
    expect(wrapper.text()).toContain('Day offer');
    expect(wrapper.text()).toContain('Only today');
    expect(wrapper.text()).toContain('More');
    expect(wrapper.text()).toContain('Buy');
    expect(wrapper.get('img').attributes('src')).toBe(
      'https://cdn.example/offer.png'
    );
    expect(wrapper.get('a').attributes('href')).toBe(
      'https://example.org/more'
    );
  });

  it('shows an article link', () => {
    messageState.content.value = 'Reading';
    messageState.contentType.value = 'article';
    messageState.contentAttributes.value = {
      items: [
        {
          title: 'Acme',
          description: 'Hardware',
          link: 'https://acme.example',
        },
      ],
    };

    const wrapper = mountBubble();

    expect(wrapper.text()).toContain('Acme');
    expect(wrapper.text()).toContain('Hardware');
    expect(wrapper.get('a').attributes('href')).toBe('https://acme.example');
  });

  it('shows the empty state when there are no items', () => {
    messageState.content.value = '';
    messageState.contentType.value = 'cards';
    messageState.contentAttributes.value = { items: [] };

    const wrapper = mountBubble();

    expect(wrapper.text()).toContain(
      'CONVERSATION.EVOLUTION_GO_STRUCTURED.EMPTY'
    );
  });
});
