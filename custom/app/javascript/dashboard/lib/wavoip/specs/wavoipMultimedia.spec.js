import { describe, expect, it, vi } from 'vitest';
import {
  applyWavoipInputDevice,
  applyWavoipOutputDevice,
  normalizeWavoipMultimediaDevices,
  readActiveMultimediaIds,
} from '../wavoipMultimedia';

describe('normalizeWavoipMultimediaDevices', () => {
  it('splits a MediaDeviceInfo array by kind', () => {
    expect(
      normalizeWavoipMultimediaDevices([
        { deviceId: 'mic-1', kind: 'audioinput' },
        { deviceId: 'spk-1', kind: 'audiooutput' },
      ])
    ).toEqual({
      inputs: [{ deviceId: 'mic-1', kind: 'audioinput' }],
      outputs: [{ deviceId: 'spk-1', kind: 'audiooutput' }],
    });
  });

  it('accepts { microphones, speakers }', () => {
    expect(
      normalizeWavoipMultimediaDevices({
        microphones: [{ deviceId: 'mic-1' }],
        speakers: [{ deviceId: 'spk-1' }],
      })
    ).toEqual({
      inputs: [{ deviceId: 'mic-1' }],
      outputs: [{ deviceId: 'spk-1' }],
    });
  });

  it('accepts legacy { inputs, outputs }', () => {
    expect(
      normalizeWavoipMultimediaDevices({
        inputs: [{ deviceId: 'mic-1' }],
        outputs: [{ deviceId: 'spk-1' }],
      })
    ).toEqual({
      inputs: [{ deviceId: 'mic-1' }],
      outputs: [{ deviceId: 'spk-1' }],
    });
  });
});

describe('readActiveMultimediaIds', () => {
  it('prefers camelCase ids, then nested MediaDeviceInfo', () => {
    expect(
      readActiveMultimediaIds({
        microphone: { deviceId: 'mic-nested' },
        speaker: { deviceUsed: { deviceId: 'spk-nested' } },
      })
    ).toEqual({ inputId: 'mic-nested', outputId: 'spk-nested' });

    expect(
      readActiveMultimediaIds({
        inputDeviceId: 'mic-legacy',
        outputDeviceId: 'spk-legacy',
      })
    ).toEqual({ inputId: 'mic-legacy', outputId: 'spk-legacy' });
  });
});

describe('applyWavoipInputDevice / applyWavoipOutputDevice', () => {
  it('uses setInputDevice / setOutputDevice when present', async () => {
    const multimedia = {
      setInputDevice: vi.fn(),
      setOutputDevice: vi.fn(),
    };

    await expect(applyWavoipInputDevice(multimedia, 'mic-1')).resolves.toBe(
      true
    );
    await expect(applyWavoipOutputDevice(multimedia, 'spk-1')).resolves.toBe(
      true
    );
    expect(multimedia.setInputDevice).toHaveBeenCalledWith('mic-1');
    expect(multimedia.setOutputDevice).toHaveBeenCalledWith('spk-1');
  });

  it('falls back to nested setDevice', async () => {
    const multimedia = {
      microphone: { setDevice: vi.fn() },
      speaker: { setDevice: vi.fn() },
    };

    await expect(applyWavoipInputDevice(multimedia, 'mic-2')).resolves.toBe(
      true
    );
    await expect(applyWavoipOutputDevice(multimedia, 'spk-2')).resolves.toBe(
      true
    );
    expect(multimedia.microphone.setDevice).toHaveBeenCalledWith('mic-2');
    expect(multimedia.speaker.setDevice).toHaveBeenCalledWith('spk-2');
  });
});
