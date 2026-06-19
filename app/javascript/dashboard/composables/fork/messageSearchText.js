export const foldDiacritics = value =>
  value.normalize('NFD').replace(/\p{M}/gu, '').toLowerCase();

export const textIncludesFoldedQuery = (text, query) => {
  const normalizedQuery = foldDiacritics(query.trim());
  if (!normalizedQuery || normalizedQuery.length < 2) return false;
  return foldDiacritics(text || '').includes(normalizedQuery);
};
