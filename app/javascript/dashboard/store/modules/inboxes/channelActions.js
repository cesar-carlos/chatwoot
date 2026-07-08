import * as types from '../../mutation-types';
import InboxesAPI from '../../../api/inboxes';
import AnalyticsHelper from '../../../helper/AnalyticsHelper';
import { ACCOUNT_EVENTS } from '../../../helper/AnalyticsHelper/events';

export const buildInboxData = inboxParams => {
  const formData = new FormData();
  const { channel = {}, ...inboxProperties } = inboxParams;
  Object.keys(inboxProperties).forEach(key => {
    formData.append(key, inboxProperties[key]);
  });
  const { selectedFeatureFlags, ...channelParams } = channel;
  // selectedFeatureFlags needs to be empty when creating a website channel
  if (selectedFeatureFlags) {
    if (selectedFeatureFlags.length) {
      selectedFeatureFlags.forEach(featureFlag => {
        formData.append(`channel[selected_feature_flags][]`, featureFlag);
      });
    } else {
      formData.append('channel[selected_feature_flags][]', '');
    }
  }
  Object.keys(channelParams).forEach(key => {
    formData.append(`channel[${key}]`, channel[key]);
  });
  return formData;
};

const sendAnalyticsEvent = channelType => {
  AnalyticsHelper.track(ACCOUNT_EVENTS.ADDED_AN_INBOX, {
    channelType,
  });
};

export const channelActions = {
  createVoiceChannel: async ({ commit }, params) => {
    try {
      commit(types.default.SET_INBOXES_UI_FLAG, { isCreating: true });
      const response = await InboxesAPI.create({
        name: params.name,
        channel: { ...params.voice, type: 'voice' },
      });
      commit(types.default.ADD_INBOXES, response.data);
      commit(types.default.SET_INBOXES_UI_FLAG, { isCreating: false });
      sendAnalyticsEvent('voice');
      return response.data;
    } catch (error) {
      commit(types.default.SET_INBOXES_UI_FLAG, { isCreating: false });
      throw error;
    }
  },
  createWavoipChannel: async ({ commit }, params) => {
    try {
      commit(types.default.SET_INBOXES_UI_FLAG, { isCreating: true });
      const response = await InboxesAPI.create({
        name: params.name,
        channel: { ...params.wavoip, type: 'wavoip' },
      });
      commit(types.default.ADD_INBOXES, response.data);
      commit(types.default.SET_INBOXES_UI_FLAG, { isCreating: false });
      sendAnalyticsEvent('wavoip');
      return response.data;
    } catch (error) {
      commit(types.default.SET_INBOXES_UI_FLAG, { isCreating: false });
      throw error;
    }
  },
  createEvolutionChannel: async ({ commit }, params) => {
    try {
      commit(types.default.SET_INBOXES_UI_FLAG, { isCreating: true });
      const response = await InboxesAPI.create(params);
      commit(types.default.ADD_INBOXES, response.data);
      commit(types.default.SET_INBOXES_UI_FLAG, { isCreating: false });
      sendAnalyticsEvent('whatsapp');
      return response.data;
    } catch (error) {
      commit(types.default.SET_INBOXES_UI_FLAG, { isCreating: false });
      throw error;
    }
  },
  createEvolutionGoChannel: async ({ commit }, params) => {
    try {
      commit(types.default.SET_INBOXES_UI_FLAG, { isCreating: true });
      const response = await InboxesAPI.create(params);
      commit(types.default.ADD_INBOXES, response.data);
      commit(types.default.SET_INBOXES_UI_FLAG, { isCreating: false });
      sendAnalyticsEvent('whatsapp');
      return response.data;
    } catch (error) {
      commit(types.default.SET_INBOXES_UI_FLAG, { isCreating: false });
      throw error;
    }
  },
  fetchInboxItem: async ({ commit }, inboxId) => {
    const response = await InboxesAPI.show(inboxId);
    commit(types.default.SET_INBOXES_ITEM, response.data);
    return response.data;
  },
  fetchEvolutionConnection: async (_ctx, inboxId) => {
    const response = await InboxesAPI.getEvolutionConnection(inboxId);
    return response.data;
  },
  evolutionReconnect: async (_ctx, inboxId) => {
    const response = await InboxesAPI.postEvolutionReconnect(inboxId);
    return response.data;
  },
  evolutionLogout: async (_ctx, inboxId) => {
    const response = await InboxesAPI.postEvolutionLogout(inboxId);
    return response.data;
  },
  evolutionRestart: async (_ctx, inboxId) => {
    const response = await InboxesAPI.postEvolutionRestart(inboxId);
    return response.data;
  },
  evolutionImport: async (_ctx, inboxId) => {
    const response = await InboxesAPI.postEvolutionImport(inboxId);
    return response.data;
  },
  fetchEvolutionGoConnection: async (_ctx, inboxId) => {
    const response = await InboxesAPI.getEvolutionGoConnection(inboxId);
    return response.data;
  },
  evolutionGoReconnect: async (_ctx, inboxId) => {
    const response = await InboxesAPI.postEvolutionGoReconnect(inboxId);
    return response.data;
  },
  evolutionGoLogout: async (_ctx, inboxId) => {
    const response = await InboxesAPI.postEvolutionGoLogout(inboxId);
    return response.data;
  },
  evolutionGoImport: async (_ctx, inboxId) => {
    const response = await InboxesAPI.postEvolutionGoImport(inboxId);
    return response.data;
  },
  evolutionGoSyncWebhook: async (_ctx, inboxId) => {
    const response = await InboxesAPI.postEvolutionGoSyncWebhook(inboxId);
    return response.data;
  },
  evolutionGoPair: async (_ctx, { inboxId, phone }) => {
    const response = await InboxesAPI.postEvolutionGoPair(inboxId, phone);
    return response.data;
  },
};
