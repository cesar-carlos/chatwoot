/* global axios */
import ApiClient from './ApiClient';

class ConversationWorkflowRulesAPI extends ApiClient {
  constructor() {
    super('conversation_workflow_rules', { accountScoped: true });
  }

  migrateLegacy() {
    return axios.post(`${this.url}/migrate_legacy`);
  }

  reorder(rules) {
    return axios.post(`${this.url}/reorder`, { rules });
  }
}

export default new ConversationWorkflowRulesAPI();
