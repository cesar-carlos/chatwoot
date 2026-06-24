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

export function formatWavoipStartCallError(err, t) {
  if (!err) return t('CONVERSATION.WAVOIP_CALL.DEVICE_NOT_READY');

  const devices = err.devices || [];
  if (devices.length > 0) {
    const detail = devices.map(d => d.reason || d.token).join('; ');
    return t('CONVERSATION.WAVOIP_CALL.START_CALL_DEVICE_FAILED', { detail });
  }

  return err.message || t('CONVERSATION.WAVOIP_CALL.DEVICE_NOT_READY');
}
