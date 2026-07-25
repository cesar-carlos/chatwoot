/* global axios */
import CacheEnabledApiClient from './CacheEnabledApiClient';

// FORK: slightly above Evolution ApiClient REQUEST_TIMEOUT (30s)
const EVOLUTION_CONNECTION_TIMEOUT_MS = 35_000;

class Inboxes extends CacheEnabledApiClient {
  constructor() {
    super('inboxes', { accountScoped: true });
  }

  // eslint-disable-next-line class-methods-use-this
  get cacheModelName() {
    return 'inbox';
  }

  getCampaigns(inboxId) {
    return axios.get(`${this.url}/${inboxId}/campaigns`);
  }

  deleteInboxAvatar(inboxId) {
    return axios.delete(`${this.url}/${inboxId}/avatar`);
  }

  getAgentBot(inboxId) {
    return axios.get(`${this.url}/${inboxId}/agent_bot`);
  }

  setAgentBot(inboxId, botId) {
    return axios.post(`${this.url}/${inboxId}/set_agent_bot`, {
      agent_bot: botId,
    });
  }

  syncTemplates(inboxId) {
    return axios.post(`${this.url}/${inboxId}/sync_templates`);
  }

  updateWhatsappBusinessManagementToken(inboxId, businessManagementToken) {
    return axios.put(
      `${this.url}/${inboxId}/whatsapp_business_management_token`,
      {
        business_management_token: businessManagementToken,
      }
    );
  }

  createCSATTemplate(inboxId, template) {
    return axios.post(`${this.url}/${inboxId}/csat_template`, {
      template,
    });
  }

  getCSATTemplateStatus(inboxId) {
    return axios.get(`${this.url}/${inboxId}/csat_template`);
  }

  analyzeCSATTemplateUtility(inboxId, template) {
    return axios.post(`${this.url}/${inboxId}/csat_template/analyze`, {
      template,
    });
  }

  resetSecret(inboxId) {
    return axios.post(`${this.url}/${inboxId}/reset_secret`);
  }

  enableWhatsappCalling(inboxId) {
    return axios.post(`${this.url}/${inboxId}/enable_whatsapp_calling`);
  }

  disableWhatsappCalling(inboxId) {
    return axios.post(`${this.url}/${inboxId}/disable_whatsapp_calling`);
  }

  setInboundCalls(inboxId, enabled) {
    return axios.post(`${this.url}/${inboxId}/set_inbound_calls`, {
      inbound_calls_enabled: enabled,
    });
  }

  // FORK: Wavoip SDK bootstrap for authorized inbox agents
  getWavoipSdkBootstrap(inboxId) {
    return axios.get(`${this.url}/${inboxId}/wavoip_sdk_bootstrap`);
  }

  getWavoipDeviceStatus(inboxId, { force = false } = {}) {
    return axios.get(`${this.url}/${inboxId}/wavoip_device_status`, {
      params: force ? { force: true } : {},
    });
  }

  getWavoipQr(inboxId, { refresh = false } = {}) {
    return axios.get(`${this.url}/${inboxId}/wavoip_qr`, {
      params: refresh ? { refresh: true } : {},
    });
  }

  postWavoipLogout(inboxId) {
    return axios.post(`${this.url}/${inboxId}/wavoip_logout`);
  }

  regenerateWavoipWebhookKey(inboxId) {
    return axios.post(`${this.url}/${inboxId}/regenerate_wavoip_webhook_key`);
  }

  testWavoipWebhook(inboxId) {
    return axios.post(`${this.url}/${inboxId}/test_wavoip_webhook`);
  }

  // FORK: Evolution connection / QR polling
  getEvolutionConnection(inboxId) {
    return axios.get(`${this.url}/${inboxId}/evolution_connection`, {
      timeout: EVOLUTION_CONNECTION_TIMEOUT_MS,
    });
  }

  postEvolutionReconnect(inboxId) {
    return axios.post(`${this.url}/${inboxId}/evolution_reconnect`);
  }

  postEvolutionLogout(inboxId) {
    return axios.post(`${this.url}/${inboxId}/evolution_logout`);
  }

  postEvolutionRestart(inboxId) {
    return axios.post(`${this.url}/${inboxId}/evolution_restart`);
  }

  postEvolutionImport(inboxId) {
    return axios.post(`${this.url}/${inboxId}/evolution_import`);
  }

  postEvolutionRefreshContacts(inboxId) {
    return axios.post(`${this.url}/${inboxId}/evolution_refresh_contacts`);
  }

  // FORK: Evolution Go connection / QR polling
  getEvolutionGoConnection(inboxId, { includeQr = false } = {}) {
    return axios.get(`${this.url}/${inboxId}/evolution_go_connection`, {
      timeout: EVOLUTION_CONNECTION_TIMEOUT_MS,
      params: includeQr ? { include_qr: true } : {},
    });
  }

  postEvolutionGoReconnect(inboxId) {
    return axios.post(`${this.url}/${inboxId}/evolution_go_reconnect`);
  }

  postEvolutionGoLogout(inboxId) {
    return axios.post(`${this.url}/${inboxId}/evolution_go_logout`);
  }

  postEvolutionGoImport(inboxId) {
    return axios.post(`${this.url}/${inboxId}/evolution_go_import`);
  }

  postEvolutionGoRefreshContacts(inboxId) {
    return axios.post(`${this.url}/${inboxId}/evolution_go_refresh_contacts`);
  }

  getEvolutionGoDiagnostics(inboxId) {
    return axios.get(`${this.url}/${inboxId}/evolution_go_diagnostics`);
  }

  postEvolutionGoTestWebhook(inboxId) {
    return axios.post(`${this.url}/${inboxId}/evolution_go_test_webhook`);
  }

  postEvolutionGoSyncWebhook(inboxId) {
    return axios.post(`${this.url}/${inboxId}/evolution_go_sync_webhook`);
  }

  postEvolutionGoPair(inboxId, phone) {
    return axios.post(`${this.url}/${inboxId}/evolution_go_pair`, { phone });
  }

  postEvolutionGoServerCheck(payload) {
    return axios.post(`${this.url}/evolution_go_server_check`, payload);
  }

  // FORK: move WhatsApp conversation history between inboxes
  postMoveHistory(inboxId, targetInboxId) {
    return axios.post(`${this.url}/${inboxId}/move_history`, {
      target_inbox_id: targetInboxId,
    });
  }

  getMoveHistoryStatus(inboxId) {
    return axios.get(`${this.url}/${inboxId}/move_history_status`);
  }
}

export default new Inboxes();
