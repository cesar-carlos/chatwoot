import { config, mount } from '@vue/test-utils';
import { afterEach, describe, expect, it } from 'vitest';
import NotificationEventDescription from 'customDashboard/components/notifications/NotificationEventDescription.vue';
import NotificationPreferences from 'dashboard/routes/dashboard/settings/profile/NotificationPreferences.vue';
import { withTeamNotificationType } from 'customDashboard/helper/teamNotificationPreferences';
import en from 'dashboard/i18n/locale/en/settings.json';
import ptBR from 'dashboard/i18n/locale/pt_BR/settings.json';
import { createI18n } from 'vue-i18n';

describe('team notification event explanation', () => {
  const plugins = config.global.plugins;
  afterEach(() => {
    config.global.plugins = plugins;
  });
  it.each([
    ['en', en, 'It does not alert for every new message.'],
    ['pt_BR', ptBR, 'Não avisa a cada nova mensagem.'],
  ])(
    'renders the explanation for %s using the shared component',
    (locale, messages, expected) => {
      const type = withTeamNotificationType([])[0];
      const i18n = createI18n({
        legacy: false,
        locale,
        messages: { [locale]: messages },
      });
      config.global.plugins = [i18n];
      const wrapper = mount(NotificationEventDescription, {
        props: { description: type.description },
      });
      expect(wrapper.text()).toContain(expected);
      expect(wrapper.get('span').classes()).toContain('block');
      wrapper.unmount();
    }
  );

  it('does not add empty copy to other event rows and registers the shared help in preferences', () => {
    const i18n = createI18n({ legacy: false, locale: 'en', messages: { en } });
    config.global.plugins = [i18n];
    const wrapper = mount(NotificationEventDescription);
    expect(wrapper.get('span').isVisible()).toBe(false);
    expect(wrapper.text()).toBe('');
    expect(
      NotificationPreferences.components.NotificationEventDescription
    ).toBe(NotificationEventDescription);
    wrapper.unmount();
  });
});
