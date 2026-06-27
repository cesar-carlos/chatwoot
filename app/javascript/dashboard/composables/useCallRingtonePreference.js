import { ref } from 'vue';
import { useStore } from 'vuex';
import { LocalStorage } from 'shared/helpers/localStorage';

const PREF_KEY_PREFIX = 'call_ringtone_muted';
const isRingtoneMuted = ref(false);

export function useCallRingtonePreference() {
  const store = useStore();

  const storageKey = () => {
    const userId = store.getters.getCurrentUserID;
    return userId ? `${PREF_KEY_PREFIX}_${userId}` : PREF_KEY_PREFIX;
  };

  const initPreference = () => {
    isRingtoneMuted.value = LocalStorage.get(storageKey()) ?? false;
  };

  const toggleRingtoneMute = () => {
    isRingtoneMuted.value = !isRingtoneMuted.value;
    LocalStorage.set(storageKey(), isRingtoneMuted.value);
  };

  return { isRingtoneMuted, initPreference, toggleRingtoneMute };
}
