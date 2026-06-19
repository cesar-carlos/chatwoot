export const TIERED_SLA_EXAMPLE_FALLBACK = [
  '15 min → add label',
  '120 min → assign team',
  '1440 min → resolve conversation',
];

export function getTieredSlaExample(tm) {
  const items = tm('CONVERSATION_RULES.FORM.TIERED_SLA_EXAMPLE');
  return Array.isArray(items) ? items : TIERED_SLA_EXAMPLE_FALLBACK;
}
