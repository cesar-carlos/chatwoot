/* global axios */

import Cookies from 'js-cookie';
import endPoints from './endPoints';
import {
  clearCookiesOnLogout,
  deleteIndexedDBOnLogout,
} from '../store/utils/api';

export default {
  validityCheck() {
    const urlData = endPoints('validityCheck');
    return axios.get(urlData.url);
  },
  profileShow() {
    return axios.get(endPoints('profileUpdate').url);
  },
  logout() {
    const urlData = endPoints('logout');
    const fetchPromise = new Promise((resolve, reject) => {
      axios
        .delete(urlData.url)
        .then(response => {
          deleteIndexedDBOnLogout();
          clearCookiesOnLogout();
          resolve(response);
        })
        .catch(error => {
          reject(error);
        });
    });
    return fetchPromise;
  },
  hasAuthCookie() {
    return !!Cookies.get('cw_d_session_info');
  },
  getAuthData() {
    if (this.hasAuthCookie()) {
      const savedAuthInfo = Cookies.get('cw_d_session_info');
      return JSON.parse(savedAuthInfo || '{}');
    }
    return false;
  },
  profileUpdate({ displayName, avatar, ...profileAttributes }) {
    // FORK: use JSON for scalar profile fields (e.g. groq_token); FormData PUT is
    // unreliable for non-file updates and can drop nested profile params.
    if (!avatar) {
      const profile = { ...profileAttributes };
      if (displayName !== undefined) {
        profile.display_name = displayName || '';
      }
      return axios.put(endPoints('profileUpdate').url, { profile });
    }

    const formData = new FormData();
    Object.keys(profileAttributes).forEach(key => {
      const hasValue = profileAttributes[key] !== undefined;
      if (hasValue) {
        formData.append(`profile[${key}]`, profileAttributes[key]);
      }
    });
    // Only send display_name when explicitly in payload; otherwise we'd overwrite
    // it with '' on partial updates (e.g. groq_token, message_signature).
    if (displayName !== undefined) {
      formData.append('profile[display_name]', displayName || '');
    }
    formData.append('profile[avatar]', avatar);
    return axios.put(endPoints('profileUpdate').url, formData);
  },

  profilePasswordUpdate({ currentPassword, password, passwordConfirmation }) {
    return axios.put(endPoints('profileUpdate').url, {
      profile: {
        current_password: currentPassword,
        password,
        password_confirmation: passwordConfirmation,
      },
    });
  },

  updateUISettings({ uiSettings }) {
    return axios.put(endPoints('profileUpdate').url, {
      profile: { ui_settings: uiSettings },
    });
  },

  updateAvailability(availabilityData) {
    return axios.post(endPoints('availabilityUpdate').url, {
      profile: { ...availabilityData },
    });
  },

  updateAutoOffline(accountId, autoOffline = false) {
    return axios.post(endPoints('autoOffline').url, {
      profile: { account_id: accountId, auto_offline: autoOffline },
    });
  },

  deleteAvatar() {
    return axios.delete(endPoints('deleteAvatar').url);
  },

  resetPassword({ email }) {
    const urlData = endPoints('resetPassword');
    return axios.post(urlData.url, { email });
  },

  setActiveAccount({ accountId }) {
    const urlData = endPoints('setActiveAccount');
    return axios.put(urlData.url, {
      profile: {
        account_id: accountId,
      },
    });
  },
  resendConfirmation() {
    const urlData = endPoints('resendConfirmation');
    return axios.post(urlData.url);
  },
  resetAccessToken() {
    const urlData = endPoints('resetAccessToken');
    return axios.post(urlData.url);
  },
  getSessions() {
    return axios.get('/api/v1/profile/sessions');
  },
  revokeSession(id) {
    return axios.delete(`/api/v1/profile/sessions/${id}`);
  },
};
