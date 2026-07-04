/* global axios */
import ApiClient from 'dashboard/api/ApiClient';

class CallsAPI extends ApiClient {
  constructor() {
    super('calls', { accountScoped: true });
  }

  recordAccept(callId) {
    return axios.patch(`${this.url}/${callId}`);
  }

  joinCall(callId) {
    return axios.post(`${this.url}/${callId}/join`);
  }
}

export default new CallsAPI();
