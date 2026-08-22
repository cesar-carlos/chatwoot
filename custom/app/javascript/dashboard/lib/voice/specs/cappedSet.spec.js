import { describe, expect, it } from 'vitest';
import { addToCappedSet, CALL_SID_SET_CAP } from '../cappedSet';

describe('addToCappedSet', () => {
  it('ignores empty values', () => {
    const set = new Set();
    addToCappedSet(set, null);
    addToCappedSet(set, undefined);
    addToCappedSet(set, '');
    expect(set.size).toBe(0);
  });

  it('evicts the oldest value once the cap is exceeded', () => {
    const set = new Set();
    addToCappedSet(set, 'first');
    for (let i = 0; i < CALL_SID_SET_CAP; i += 1) {
      addToCappedSet(set, `sid-${i}`);
    }

    expect(set.has('first')).toBe(false);
    expect(set.has(`sid-${CALL_SID_SET_CAP - 1}`)).toBe(true);
    expect(set.size).toBe(CALL_SID_SET_CAP);
  });

  it('moves a repeated value to the newest position', () => {
    const set = new Set();
    addToCappedSet(set, 'keep');
    for (let i = 0; i < CALL_SID_SET_CAP - 1; i += 1) {
      addToCappedSet(set, `sid-${i}`);
    }
    addToCappedSet(set, 'keep');
    addToCappedSet(set, 'overflow');

    expect(set.has('keep')).toBe(true);
    expect(set.has('sid-0')).toBe(false);
  });
});
