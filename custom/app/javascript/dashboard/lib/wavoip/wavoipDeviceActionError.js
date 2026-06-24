export function formatWavoipDeviceActionError(error, t) {
  const status = error?.response?.status;
  if (status === 503 || status === 502 || status === 504) {
    return t('INBOX_MGMT.WAVOIP_CALL.DEVICE_STATUS.SERVICE_UNAVAILABLE');
  }

  const message =
    error?.response?.data?.message || error?.response?.data?.error;
  if (typeof message === 'string' && message.trim()) {
    return message;
  }

  if (error?.message) {
    return error.message;
  }

  return t('INBOX_MGMT.WAVOIP_CALL.DEVICE_STATUS.ACTION_FAILED');
}
