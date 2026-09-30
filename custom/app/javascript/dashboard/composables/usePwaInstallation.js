import { computed, ref } from 'vue';
import { isPwaStandalone } from 'customDashboard/helper/pushHelper';

const installPrompt = ref(null);
const installed = ref(false);
let initialized = false;

const isIosDevice = () =>
  /iPad|iPhone|iPod/.test(navigator.userAgent) ||
  (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);

const handleInstallPrompt = event => {
  event.preventDefault();
  installPrompt.value = event;
};

const handleInstalled = () => {
  installed.value = true;
  installPrompt.value = null;
};

export const initializePwaInstallation = () => {
  if (initialized) return;

  initialized = true;
  installed.value = isPwaStandalone();
  window.addEventListener('beforeinstallprompt', handleInstallPrompt);
  window.addEventListener('appinstalled', handleInstalled);
};

export const usePwaInstallation = () => {
  initializePwaInstallation();

  const status = computed(() => {
    if (installed.value || isPwaStandalone()) return 'installed';
    if (installPrompt.value) return 'available';
    if (isIosDevice()) return 'ios_instructions';

    const hasManifest = Boolean(document.querySelector('link[rel="manifest"]'));
    return window.isSecureContext && hasManifest
      ? 'unavailable'
      : 'unsupported';
  });

  const promptInstall = async () => {
    const prompt = installPrompt.value;
    if (!prompt) return { outcome: 'unavailable' };

    await prompt.prompt();
    const choice = await prompt.userChoice;
    installPrompt.value = null;
    return choice;
  };

  return { status, promptInstall };
};
