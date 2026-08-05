/* global axios */
import ApiClient from './ApiClient';

class ConversationWorkflowRulesAPI extends ApiClient {
  constructor() {
    super('conversation_workflow_rules', { accountScoped: true });
  }

  migrateLegacy() {
    return axios.post(`${this.url}/migrate_legacy`);
  }

  previewCount(payload) {
    return axios.post(`${this.url}/preview_count`, payload);
  }

  reorder(rules) {
    return axios.post(`${this.url}/reorder`, { rules });
  }

  activity(id) {
    return axios.get(`${this.url}/${id}/activity`);
  }
}

export default new ConversationWorkflowRulesAPI();
