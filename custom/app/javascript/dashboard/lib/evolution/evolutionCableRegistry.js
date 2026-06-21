import { useAlert } from 'dashboard/composables';
import i18n from 'dashboard/i18n';

export function onEvolutionConnectionClosed(data) {
  useAlert(
    i18n.global.t('INBOX_MGMT.EVOLUTION.SETTINGS.HEALTH.DISCONNECTED_ALERT', {
      inbox: data.inbox_name,
    })
  );
}
