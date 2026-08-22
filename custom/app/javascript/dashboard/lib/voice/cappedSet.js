export const CALL_SID_SET_CAP = 200;

export function addToCappedSet(set, value) {
  if (!value || !set) return set;

  if (set.has(value)) set.delete(value);
  set.add(value);

  while (set.size > CALL_SID_SET_CAP) {
    set.delete(set.values().next().value);
  }

  return set;
}
