import { describe, expect, it } from 'vitest';
import {
  iceConfigFromBootstrap,
  wavoipIceConfigKey,
} from '../wavoipIceConfig';

describe('iceConfigFromBootstrap', () => {
  it('returns undefined when bootstrap has no servers', () => {
    expect(iceConfigFromBootstrap({})).toBeUndefined();
    expect(iceConfigFromBootstrap(null)).toBeUndefined();
  });

  it('maps ice_servers into SDK IceConfig', () => {
    expect(
      iceConfigFromBootstrap({
        ice_servers: [
          { urls: ['stun:stun.l.google.com:19302'] },
          {
            urls: 'turn:turn.example:3478',
            username: 'user',
            credential: 'secret',
          },
        ],
      })
    ).toEqual({
      iceServers: [
        { urls: ['stun:stun.l.google.com:19302'] },
        {
          urls: 'turn:turn.example:3478',
          username: 'user',
          credential: 'secret',
        },
      ],
    });
  });
});

describe('wavoipIceConfigKey', () => {
  it('is empty without servers and stable with the same list', () => {
    expect(wavoipIceConfigKey(undefined)).toBe('');
    const config = { iceServers: [{ urls: 'stun:a' }] };
    expect(wavoipIceConfigKey(config)).toBe(wavoipIceConfigKey(config));
    expect(wavoipIceConfigKey(config)).not.toBe(
      wavoipIceConfigKey({ iceServers: [{ urls: 'stun:b' }] })
    );
  });
});
