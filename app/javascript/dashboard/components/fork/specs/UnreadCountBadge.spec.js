import { mount } from '@vue/test-utils';
import { describe, expect, it } from 'vitest';
import UnreadCountBadge from '../UnreadCountBadge.vue';

const renderComponent = count =>
  mount(UnreadCountBadge, {
    props: { count },
  });

describe('UnreadCountBadge', () => {
  it('does not render when count is 0', () => {
    const wrapper = renderComponent(0);

    expect(wrapper.find('[data-test-id="conversation-unread-badge"]').exists()).toBe(
      false
    );
  });

  it('renders count when count is between 1 and 9', () => {
    const wrapper = renderComponent(1);

    expect(wrapper.find('[data-test-id="conversation-unread-badge"]').text()).toBe(
      '1'
    );
  });

  it('renders 9 when count is 9', () => {
    const wrapper = renderComponent(9);

    expect(wrapper.find('[data-test-id="conversation-unread-badge"]').text()).toBe(
      '9'
    );
  });

  it('renders 9+ when count is greater than 9', () => {
    const wrapper = renderComponent(10);

    expect(wrapper.find('[data-test-id="conversation-unread-badge"]').text()).toBe(
      '9+'
    );
  });

  it('renders 9+ for very large counts', () => {
    const wrapper = renderComponent(99);

    expect(wrapper.find('[data-test-id="conversation-unread-badge"]').text()).toBe(
      '9+'
    );
  });
});
