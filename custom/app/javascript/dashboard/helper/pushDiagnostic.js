export const classifyPushDiagnosticError = error => {
  const status = error.response?.status;
  const reasons = {
    401: 'session',
    403: 'session',
    404: 'missing',
    422: 'invalid',
    429: 'limited',
    502: 'delivery',
  };
  if (reasons[status]) return { kind: reasons[status] };
  if (
    [
      'ECONNABORTED',
      'ETIMEDOUT',
      'ERR_CANCELED',
      'PUSH_WORKER_TIMEOUT',
    ].includes(error.code)
  )
    return { kind: 'timeout' };
  return { kind: 'connection' };
};
