/* global axios */
import CacheEnabledApiClient from './CacheEnabledApiClient';

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
    return axios.get(`${this.url}/${inboxId}/evolution_connection`);
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

  // FORK: Evolution Go connection / QR polling
  getEvolutionGoConnection(inboxId) {
    return axios.get(`${this.url}/${inboxId}/evolution_go_connection`);
  }

  postEvolutionGoReconnect(inboxId) {
    return axios.post(`${this.url}/${inboxId}/evolution_go_reconnect`);
  }

  postEvolutionGoServerCheck(payload) {
    return axios.post(`${this.url}/evolution_go_server_check`, payload);
  }
}

export default new Inboxes();
