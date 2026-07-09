import { textIncludesFoldedQuery } from './messageSearchText';

export const readEmailSubject = message => {
  const attrs = message?.content_attributes || {};
  return attrs.email?.subject || '';
};

/**
 * Pick the text shown in a search result row.
 * Prefer subject when the query matches subject but not body.
 */
export const buildSearchResultDisplayMessage = ({
  message,
  searchQuery,
  transcriptText = '',
}) => {
  const subject = readEmailSubject(message);
  const bodyMatch = textIncludesFoldedQuery(message?.content, searchQuery);
  const subjectMatch = textIncludesFoldedQuery(subject, searchQuery);
  const transcriptionMatch =
    message?.matched_on === 'transcription' ||
    textIncludesFoldedQuery(transcriptText, searchQuery);
  const contentMatch =
    bodyMatch || subjectMatch || message?.matched_on === 'content';

  if (subjectMatch && !bodyMatch && subject) {
    return { ...message, content: subject };
  }

  if (bodyMatch) {
    return message;
  }

  if (contentMatch && !transcriptionMatch) {
    return message;
  }

  if (transcriptionMatch && transcriptText) {
    return { ...message, content: transcriptText };
  }

  if (message?.content?.trim()) {
    return message;
  }

  if (subject) {
    return { ...message, content: subject };
  }

  if (!transcriptText) {
    return message;
  }

  return { ...message, content: transcriptText };
};
