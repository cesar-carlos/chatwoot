/* global axios */
import ApiClient from './ApiClient';

class ServiceSessionReportsAPI extends ApiClient {
  constructor() {
    super('service_session_reports', { accountScoped: true, apiVersion: 'v2' });
  }

  summary(params = {}) {
    return this.fetchData('summary', params);
  }

  open(params = {}) {
    return this.fetchData('open', params);
  }

  closed(params = {}) {
    return this.fetchData('closed', params);
  }

  byAgent(params = {}) {
    return this.fetchData('by_agent', params);
  }

  byInbox(params = {}) {
    return this.fetchData('by_inbox', params);
  }

  byTeam(params = {}) {
    return this.fetchData('by_team', params);
  }

  byLabel(params = {}) {
    return this.fetchData('by_label', params);
  }

  fetchData(
    path,
    {
      since,
      until,
      businessHours,
      inboxId,
      teamId,
      userIds,
      labelIds,
      page,
      perPage,
    } = {}
  ) {
    return axios.get(`${this.url}/${path}`, {
      params: {
        since,
        until,
        business_hours: businessHours,
        inbox_id: inboxId,
        team_id: teamId,
        user_ids: userIds,
        label_ids: labelIds,
        page,
        per_page: perPage,
      },
    });
  }
}

export default new ServiceSessionReportsAPI();
