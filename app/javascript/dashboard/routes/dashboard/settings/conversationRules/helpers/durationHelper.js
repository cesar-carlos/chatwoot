import { DURATION_UNITS } from 'dashboard/components-next/input/constants';

export function inferDurationUnit(minutes) {
  if (!minutes) return DURATION_UNITS.MINUTES;
  if (minutes % (24 * 60) === 0) return DURATION_UNITS.DAYS;
  if (minutes % 60 === 0) return DURATION_UNITS.HOURS;
  return DURATION_UNITS.MINUTES;
}

export function formatWorkflowDuration(minutes, t) {
  if (!minutes) return '';

  const unit = inferDurationUnit(minutes);
  let value = minutes;

  if (unit === DURATION_UNITS.DAYS) {
    value = minutes / (24 * 60);
    return t('CONVERSATION_RULES.DURATION.DAYS', { count: value });
  }

  if (unit === DURATION_UNITS.HOURS) {
    value = minutes / 60;
    return t('CONVERSATION_RULES.DURATION.HOURS', { count: value });
  }

  return t('CONVERSATION_RULES.DURATION.MINUTES', { count: value });
}
