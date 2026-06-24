export const MAX_SEARCH_INJECTED_MESSAGES = 50;

export const collectVisibleMessageIds = () => {
  const panel = document.querySelector('.conversation-panel');
  if (!panel || typeof document === 'undefined') return [];

  const panelRect = panel.getBoundingClientRect();
  const ids = [];

  panel.querySelectorAll('[id^="message"]').forEach(element => {
    const rect = element.getBoundingClientRect();
    if (rect.bottom < panelRect.top || rect.top > panelRect.bottom) return;

    const match = element.id.match(/^message(\d+)$/);
    if (match) ids.push(Number(match[1]));
  });

  return ids;
};

export const newMessageIds = (existingMessages, incomingMessages) => {
  const existingIds = new Set(
    (existingMessages || []).map(message => message.id)
  );
  return (incomingMessages || [])
    .map(message => message.id)
    .filter(id => !existingIds.has(id));
};
