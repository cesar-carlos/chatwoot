/* global axios */
import ApiClient from 'dashboard/api/ApiClient';

class CallsAPI extends ApiClient {
  constructor() {
    super('calls', { accountScoped: true });
  }

  recordAccept(callId) {
    return axios.patch(`${this.url}/${callId}`);
  }
}

export default new CallsAPI();
