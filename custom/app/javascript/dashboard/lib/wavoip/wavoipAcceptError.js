/**
 * Typed accept/join failure so useCallSession can show a specific i18n alert
 * instead of the generic CONTACT_PANEL.CALL_FAILED toast.
 */
export function createWavoipAcceptError(i18nKey, cause) {
  const error = new Error(i18nKey);
  error.i18nKey = i18nKey;
  if (cause) error.cause = cause;
  return error;
}

export function isWavoipAcceptError(error) {
  return Boolean(error?.i18nKey);
}
