import { onMounted, onUnmounted, ref, watch } from 'vue';
import {
  getPushEnvironment,
  isPwaStandalone,
  isPushOptedOut,
} from 'customDashboard/helper/pushHelper';
import {
  isPushSessionActive,
  pushSession,
} from 'customDashboard/helper/pushSession';

export const pushInvitationKey = userId =>
  `chatwoot:push-invitation:v1:${userId}`;

export const usePwaPushInvitation = (props, status) => {
  const open = ref(false);
  let observer;
  let mounted = false;
  let storageUnavailable = false;
  const evaluate = () => {
    if (
      !mounted ||
      storageUnavailable ||
      open.value ||
      !props.ready ||
      !isPushSessionActive()
    )
      return;
    if (!pushSession().identity || !props.user?.id || !isPwaStandalone())
      return;
    const membership = props.user.accounts?.find(
      account => String(account.id) === String(props.accountId)
    );
    if (membership?.status !== 'active' || !getPushEnvironment().supported)
      return;
    if (!['default', 'denied', 'unsubscribed'].includes(status.value)) return;
    try {
      if (isPushOptedOut()) return;
      const key = pushInvitationKey(props.user.id);
      if (localStorage.getItem(key)) return;
      if (document.querySelector('dialog[open]')) {
        observer.observe(document.body, {
          childList: true,
          subtree: true,
          attributes: true,
          attributeFilter: ['open'],
        });
        return;
      }
      // Persist before opening so refreshes and other tabs do not repeat it.
      localStorage.setItem(key, 'shown');
      observer.disconnect();
      open.value = true;
    } catch (error) {
      storageUnavailable = true;
      // Do not repeatedly invite when browser storage is unavailable.
      // eslint-disable-next-line no-console
      console.error('Push invitation storage is unavailable');
    }
  };
  watch(
    () => [
      props.user?.id,
      props.accountId,
      props.ready,
      props.user?.accounts?.find(
        account => String(account.id) === String(props.accountId)
      )?.status,
    ],
    () => {
      open.value = false;
      observer?.disconnect();
      evaluate();
    }
  );
  watch(status, evaluate);
  const close = () => {
    open.value = false;
    observer?.disconnect();
  };
  const handleStorage = event => {
    if (
      event.key === pushInvitationKey(props.user?.id) ||
      (event.key === 'chatwoot_push_enabled' && event.newValue === 'false')
    )
      close();
  };
  onMounted(() => {
    mounted = true;
    observer = new MutationObserver(evaluate);
    window.addEventListener('storage', handleStorage);
    evaluate();
  });
  onUnmounted(() => {
    mounted = false;
    observer?.disconnect();
    window.removeEventListener('storage', handleStorage);
  });
  return { open, close };
};
