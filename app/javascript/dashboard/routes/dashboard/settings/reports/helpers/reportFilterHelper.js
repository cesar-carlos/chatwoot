export const generateReportURLParams = ({
  from,
  to,
  businessHours,
  groupBy,
  range,
}) => {
  const params = {};

  // Always include from/to dates
  if (from) params.from = from;
  if (to) params.to = to;

  if (businessHours) params.business_hours = 'true';
  if (groupBy) params.group_by = groupBy;

  // Include range type (last7days, last3months, custom, etc.)
  if (range) params.range = range;

  return params;
};

export const parseReportURLParams = query => {
  const { from, to, business_hours, group_by, range } = query;

  return {
    from: from ? Number(from) : null,
    to: to ? Number(to) : null,
    businessHours: business_hours === 'true',
    groupBy: group_by ? Number(group_by) : null,
    range: range || null,
  };
};

// Parse filter params from URL (agent_id, inbox_id, team_id, sla_policy_id, label, rating)
export const parseFilterURLParams = query => {
  return {
    agent_id: query.agent_id ? Number(query.agent_id) : null,
    inbox_id: query.inbox_id ? Number(query.inbox_id) : null,
    team_id: query.team_id ? Number(query.team_id) : null,
    sla_policy_id: query.sla_policy_id ? Number(query.sla_policy_id) : null,
    label: query.label || null,
    rating: query.rating ? Number(query.rating) : null,
  };
};

// Generate filter URL params (only include non-null values)
export const generateFilterURLParams = filters => {
  const params = {};
  if (filters.agent_id) params.agent_id = filters.agent_id;
  if (filters.inbox_id) params.inbox_id = filters.inbox_id;
  if (filters.team_id) params.team_id = filters.team_id;
  if (filters.sla_policy_id) params.sla_policy_id = filters.sla_policy_id;
  if (filters.label) params.label = filters.label;
  if (filters.rating) params.rating = filters.rating;
  return params;
};

// Merge date range and filter params for complete URL
export const generateCompleteURLParams = ({
  from,
  to,
  range,
  filters = {},
}) => {
  const dateParams = generateReportURLParams({ from, to, range });
  const filterParams = generateFilterURLParams(filters);
  return { ...dateParams, ...filterParams };
};

// FORK: service session report entity filter URL params
export const parseServiceSessionEntityURLParams = query => ({
  inbox_id: query.inbox_id ? Number(query.inbox_id) : null,
  team_id: query.team_id ? Number(query.team_id) : null,
  user_ids: query.user_ids ? Number(query.user_ids) : null,
  label_ids: query.label_ids ? Number(query.label_ids) : null,
});

export const generateServiceSessionEntityURLParams = filters => {
  const params = {};
  if (filters.inbox_id) params.inbox_id = filters.inbox_id;
  if (filters.team_id) params.team_id = filters.team_id;
  if (filters.user_ids) params.user_ids = filters.user_ids;
  if (filters.label_ids) params.label_ids = filters.label_ids;
  return params;
};

// FORK: service session open/closed list pagination URL param
export const parseServiceSessionListURLParams = query => ({
  page: query.page ? Number(query.page) : 1,
});

export const generateServiceSessionListURLParams = ({ page } = {}) => {
  const params = {};
  if (page && page > 1) params.page = page;
  return params;
};
