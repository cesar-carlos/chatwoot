/* global axios */
import ApiClient from './ApiClient';

class ConversationMessageSearchAPI extends ApiClient {
  constructor() {
    super('conversations', { accountScoped: true });
  }

  search({ conversationId, query, page = 1, from, signal }) {
    return axios.get(`${this.url}/${conversationId}/messages/search`, {
      params: {
        q: query,
        page,
        ...(from ? { from } : {}),
      },
      signal,
    });
  }
}

export default new ConversationMessageSearchAPI();
