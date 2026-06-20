export const resolveConversationMessageSearchError = (error, t) => {
  const status = error?.response?.status;
  const serverError = error?.response?.data?.error?.toString().trim();

  if (status === 429) {
    return t('CONVERSATION.MESSAGE_SEARCH.ERROR_RATE_LIMIT');
  }

  if (status === 422 && serverError) {
    if (serverError.includes('between 2 and 200')) {
      return t('CONVERSATION.MESSAGE_SEARCH.ERROR_QUERY_LENGTH');
    }
    if (serverError.toLowerCase().includes('required')) {
      return t('CONVERSATION.MESSAGE_SEARCH.ERROR_QUERY_REQUIRED');
    }
    if (serverError.includes('positive integer')) {
      return t('CONVERSATION.MESSAGE_SEARCH.ERROR_PAGE');
    }
  }

  if (serverError) return serverError;

  if (status === 404) {
    return t('CONVERSATION.404');
  }

  return t('CONVERSATION.MESSAGE_SEARCH.ERROR');
};
