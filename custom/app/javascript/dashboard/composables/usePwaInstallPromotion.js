import { computed, onMounted, onUnmounted, ref, watch } from 'vue';
import { getInstallationPlatform } from './usePwaInstallation';
import {
  isPushSessionActive,
  pushSession,
} from 'customDashboard/helper/pushSession';

export const installDismissalKey = userId =>
  `chatwoot:install-promotion:v1:${userId}`;

export const usePwaInstallPromotion = (context, status) => {
  const dismissed = ref(false);
  const mobile = getInstallationPlatform() !== 'DESKTOP';
  const readDismissal = () => {
    try {
      dismissed.value = Boolean(
        localStorage.getItem(installDismissalKey(context.user?.id))
      );
    } catch (error) {
      // Avoid repeatedly promoting an app when persistence cannot be guaranteed.
      dismissed.value = true;
    }
  };
  const visible = computed(() => {
    if (
      !mobile ||
      dismissed.value ||
      !context.ready ||
      status.value === 'installed' ||
      !isPushSessionActive()
    )
      return false;
    if (!context.user?.id || !pushSession().identity) return false;
    return context.user.accounts?.some(
      account =>
        String(account.id) === String(context.accountId) &&
        account.status === 'active'
    );
  });
  const dismiss = () => {
    dismissed.value = true;
    try {
      localStorage.setItem(installDismissalKey(context.user.id), 'dismissed');
    } catch (error) {
      // The in-memory dismissal still applies to this mounted dashboard.
    }
  };
  const onStorage = event => {
    if (event.key === installDismissalKey(context.user?.id)) readDismissal();
  };
  watch(() => context.user?.id, readDismissal, { immediate: true });
  onMounted(() => window.addEventListener('storage', onStorage));
  onUnmounted(() => window.removeEventListener('storage', onStorage));
  return { visible, dismiss };
};
