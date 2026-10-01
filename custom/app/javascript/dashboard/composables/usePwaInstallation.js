import { computed, ref } from 'vue';
import { isPwaStandalone } from 'customDashboard/helper/pushHelper';

const installPrompt = ref(null);
const installed = ref(false);
const manifestStatus = ref(null);
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

  const checkInstallability = async () => {
    const manifestLink = document.querySelector('link[rel="manifest"]');
    if (!window.isSecureContext || !manifestLink) return;

    let manifest;
    try {
      const response = await fetch(manifestLink.href);
      if (!response.ok) throw new Error('Manifest unavailable');
      manifest = await response.json();
      if (
        !(manifest.name || manifest.short_name) ||
        !manifest.start_url ||
        !['standalone', 'fullscreen', 'minimal-ui'].includes(manifest.display)
      ) {
        throw new Error('Manifest missing installability fields');
      }
    } catch (error) {
      manifestStatus.value = 'manifest_error';
      return;
    }

    let iconUrls;
    try {
      iconUrls = [192, 512].map(size => {
        const icon = manifest.icons?.find(
          item =>
            item.type === 'image/png' &&
            item.sizes?.split(/\s+/).includes(`${size}x${size}`)
        );
        return icon && new URL(icon.src, manifestLink.href);
      });
    } catch (error) {
      manifestStatus.value = 'icon_error';
      return;
    }

    if (iconUrls.some(url => !url || url.origin !== window.location.origin)) {
      manifestStatus.value = 'icon_error';
      return;
    }

    try {
      const responses = await Promise.all(iconUrls.map(url => fetch(url.href)));
      manifestStatus.value = responses.every(
        response =>
          response.ok &&
          response.headers.get('content-type')?.startsWith('image/png')
      )
        ? 'valid'
        : 'icon_error';
    } catch (error) {
      manifestStatus.value = 'icon_error';
    }
  };

  const status = computed(() => {
    if (installed.value || isPwaStandalone()) return 'installed';
    if (installPrompt.value) return 'available';
    if (isIosDevice()) return 'ios_instructions';

    const hasManifest = Boolean(document.querySelector('link[rel="manifest"]'));
    if (!window.isSecureContext || !hasManifest) return 'unsupported';
    return manifestStatus.value === 'manifest_error' ||
      manifestStatus.value === 'icon_error'
      ? manifestStatus.value
      : 'unavailable';
  });

  const promptInstall = async () => {
    const prompt = installPrompt.value;
    if (!prompt) return { outcome: 'unavailable' };

    await prompt.prompt();
    const choice = await prompt.userChoice;
    installPrompt.value = null;
    return choice;
  };

  return { status, promptInstall, checkInstallability };
};
