/**
 * Normalizes @wavoip/wavoip-api return shapes ({ call, err } vs legacy direct call).
 */
export function unwrapWavoipSdkResult(result, valueKey = 'call') {
  if (!result || typeof result !== 'object') {
    return { [valueKey]: result ?? null, err: null };
  }

  if (valueKey in result || 'err' in result) {
    return {
      [valueKey]: result[valueKey] ?? null,
      err: result.err ?? null,
    };
  }

  if (
    valueKey === 'call' &&
    (typeof result.end === 'function' || typeof result.mute === 'function')
  ) {
    return { call: result, err: null };
  }

  return { [valueKey]: null, err: result };
}

const SIMULTANEOUS_LIMIT_PATTERN =
  /SIMULTANEOUS_LIMIT|simultaneous.?limit|channels?.?full/i;

const deviceFailureReasons = err => {
  const devices = err?.devices || [];
  return devices.map(d => d.reason || d.token || '').filter(Boolean);
};

const isSimultaneousLimitError = err => {
  const reasons = deviceFailureReasons(err);
  if (reasons.some(reason => SIMULTANEOUS_LIMIT_PATTERN.test(String(reason)))) {
    return true;
  }

  const message = err?.message || err?.code || err?.reason || '';
  return SIMULTANEOUS_LIMIT_PATTERN.test(String(message));
};

export function formatWavoipStartCallError(err, t) {
  if (!err) return t('CONVERSATION.WAVOIP_CALL.DEVICE_NOT_READY');

  if (isSimultaneousLimitError(err)) {
    return t('CONVERSATION.WAVOIP_CALL.CHANNELS_FULL');
  }

  const reasons = deviceFailureReasons(err);
  if (reasons.length > 0) {
    return t('CONVERSATION.WAVOIP_CALL.START_CALL_DEVICE_FAILED', {
      detail: reasons.join('; '),
    });
  }

  return err.message || t('CONVERSATION.WAVOIP_CALL.DEVICE_NOT_READY');
}

const PEER_REJECT_PERMISSION_PATTERN =
  /138006|permission|not authorized|not allowed|call permission/i;

export function formatWavoipPeerRejectError(reason, t) {
  const message =
    typeof reason === 'string'
      ? reason
      : reason?.message || reason?.code || reason?.reason || '';

  if (PEER_REJECT_PERMISSION_PATTERN.test(String(message))) {
    return t('CONVERSATION.WAVOIP_CALL.OUTBOUND_PERMISSION_DENIED');
  }

  return t('CONVERSATION.WAVOIP_CALL.PEER_REJECTED');
}
