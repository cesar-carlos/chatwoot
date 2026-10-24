import { flushPromises, mount } from '@vue/test-utils';
import { useAlert } from 'dashboard/composables';
import ShareContactForm from './ShareContactForm.vue';

const { searchContacts } = vi.hoisted(() => ({
  searchContacts: vi.fn(),
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: '3' } }),
}));

vi.mock('@chatwoot/utils', () => ({
  debounce: fn => fn,
}));

vi.mock(
  'dashboard/components-next/NewConversation/helpers/composeConversationHelper',
  () => ({
    createContactSearcher: () => searchContacts,
  })
);

vi.mock('dashboard/composables', () => ({
  useAlert: vi.fn(),
}));

const ComboBoxStub = {
  name: 'ComboBox',
  props: ['emptyState', 'options'],
  template: '<div class="combobox">{{ emptyState }}</div>',
};

const mountForm = (conversationContact = { id: 9, name: 'Ada' }) =>
  mount(ShareContactForm, {
    props: { conversationContact },
    global: {
      stubs: {
        Avatar: true,
        ComboBox: ComboBoxStub,
        RouterLink: {
          name: 'RouterLink',
          props: ['to'],
          template: '<a :href="to"><slot /></a>',
        },
      },
    },
  });

describe('ShareContactForm', () => {
  beforeEach(() => {
    searchContacts.mockReset();
    useAlert.mockReset();
  });

  it('shares the conversation contact without submitting the dialog form', async () => {
    const wrapper = mountForm({
      id: 9,
      name: 'Ada Lovelace',
      phone_number: '+5511999999999',
    });

    const button = wrapper.get('button');
    expect(button.attributes('type')).toBe('button');
    await button.trigger('click');

    expect(wrapper.emitted('quickShare')[0][0]).toMatchObject({
      id: 9,
      phone_number: '+5511999999999',
    });
    wrapper.unmount();
  });

  it('shows the missing-phone message and an edit link', () => {
    const wrapper = mountForm({ id: 9, name: 'Ada Lovelace' });

    expect(wrapper.text()).toContain(
      'CONVERSATION.SHARE_CONTACT.MODAL.NO_PHONE_CURRENT'
    );
    expect(wrapper.get('a').attributes('href')).toBe(
      '/app/accounts/3/contacts/9'
    );
    expect(wrapper.find('button').exists()).toBe(false);
    wrapper.unmount();
  });

  it('tells the agent when search matches have no phone number', async () => {
    searchContacts.mockResolvedValue([
      { id: 4, name: 'Email only', email: 'ada@example.com' },
    ]);
    const wrapper = mountForm();

    await wrapper.findComponent(ComboBoxStub).vm.$emit('search', 'ada');
    await flushPromises();

    expect(wrapper.get('.combobox').text()).toContain(
      'CONVERSATION.SHARE_CONTACT.MODAL.NO_PHONE'
    );
    wrapper.unmount();
  });
});
