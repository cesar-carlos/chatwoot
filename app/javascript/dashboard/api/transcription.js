/* global axios */
import ApiClient from './ApiClient';

class TranscriptionAPI extends ApiClient {
  constructor() {
    super('transcriptions', { accountScoped: true });
  }

  transcribe(formData) {
    return axios.post(this.url, formData, {
      headers: {
        'Content-Type': 'multipart/form-data',
      },
      timeout: 65000,
    });
  }

  getPresets() {
    return axios.get(`${this.url}/presets`);
  }
}

export default new TranscriptionAPI();
