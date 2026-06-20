export const isEditableTarget = target => {
  if (!target) return false;

  if (target.isContentEditable) return true;

  const tagName = target.tagName;
  return tagName === 'INPUT' || tagName === 'TEXTAREA' || tagName === 'SELECT';
};
