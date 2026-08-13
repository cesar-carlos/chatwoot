/**
 * Normalizes @wavoip/wavoip-api multimedia shapes across 2.6.x docs:
 * - MediaDeviceInfo[] (current gitbook)
 * - { microphones, speakers }
 * - { inputs, outputs } (legacy Chatwoot)
 */
export function normalizeWavoipMultimediaDevices(devices) {
  if (!devices) return { inputs: [], outputs: [] };

  if (Array.isArray(devices)) {
    return {
      inputs: devices.filter(device => isAudioInput(device)),
      outputs: devices.filter(device => isAudioOutput(device)),
    };
  }

  return {
    inputs: devices.inputs || devices.microphones || [],
    outputs: devices.outputs || devices.speakers || [],
  };
}

export function readActiveMultimediaIds(multimedia) {
  if (!multimedia) return { inputId: null, outputId: null };

  return {
    inputId:
      multimedia.inputDeviceId ||
      deviceIdOf(multimedia.microphone) ||
      null,
    outputId:
      multimedia.outputDeviceId ||
      deviceIdOf(multimedia.speaker) ||
      null,
  };
}

export async function applyWavoipInputDevice(multimedia, deviceId) {
  return applyMultimediaDevice(multimedia, deviceId, [
    'setInputDevice',
    'setMicrophone',
    'microphone',
  ]);
}

export async function applyWavoipOutputDevice(multimedia, deviceId) {
  return applyMultimediaDevice(multimedia, deviceId, [
    'setOutputDevice',
    'setSpeaker',
    'speaker',
  ]);
}

const isAudioInput = device =>
  device?.kind === 'audioinput' || device?.kind === 'audioInput';

const isAudioOutput = device =>
  device?.kind === 'audiooutput' || device?.kind === 'audioOutput';

const deviceIdOf = device =>
  device?.deviceId || device?.deviceUsed?.deviceId || null;

const applyMultimediaDevice = async (
  multimedia,
  deviceId,
  [setterA, setterB, nestedKey]
) => {
  if (!multimedia || !deviceId) return false;

  if (typeof multimedia[setterA] === 'function') {
    await multimedia[setterA](deviceId);
    return true;
  }
  if (typeof multimedia[setterB] === 'function') {
    await multimedia[setterB](deviceId);
    return true;
  }

  const nested = multimedia[nestedKey];
  if (typeof nested?.setDevice === 'function') {
    await nested.setDevice(deviceId);
    return true;
  }
  if (typeof nested?.select === 'function') {
    await nested.select(deviceId);
    return true;
  }

  return false;
};
