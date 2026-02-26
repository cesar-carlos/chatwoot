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

    expect(wrapper.text()).toBe('');
  });

  it('renders count when count is between 1 and 9', () => {
    const wrapper = renderComponent(1);

    expect(wrapper.text()).toBe('1');
  });

  it('renders 9 when count is 9', () => {
    const wrapper = renderComponent(9);

    expect(wrapper.text()).toBe('9');
  });

  it('renders 9+ when count is greater than 9', () => {
    const wrapper = renderComponent(10);

    expect(wrapper.text()).toBe('9+');
  });

  it('does not render for null count', () => {
    const wrapper = renderComponent(null);

    expect(wrapper.text()).toBe('');
  });

  it('does not render for undefined count', () => {
    const wrapper = renderComponent(undefined);

    expect(wrapper.text()).toBe('');
  });

  it('normalizes numeric strings', () => {
    const wrapper = renderComponent('3');

    expect(wrapper.text()).toBe('3');
  });

  it('does not render for negative count', () => {
    const wrapper = renderComponent(-1);

    expect(wrapper.text()).toBe('');
  });
});
