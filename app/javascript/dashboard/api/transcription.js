/* global axios */
import ApiClient from './ApiClient';

class TranscriptionAPI extends ApiClient {
  constructor() {
    super('transcriptions', { accountScoped: true });
  }

  transcribe(formData) {
    // Let browser set Content-Type with proper boundary for multipart/form-data
    return axios.post(this.url, formData, {
      timeout: 65000,
    });
  }

  getPresets() {
    return axios.get(`${this.url}/presets`);
  }
}

export default new TranscriptionAPI();
