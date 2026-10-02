import { computed, ref } from 'vue';
import { isPwaStandalone } from 'customDashboard/helper/pushHelper';

const installPrompt = ref(null);
const installed = ref(false);
const manifestStatus = ref(null);
const busy = ref(false);
const standalone = ref(false);
let checking;
let initialized = false;

const isIosDevice = () =>
  /iPad|iPhone|iPod/.test(navigator.userAgent) ||
  (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);

export const getInstallationPlatform = () => {
  if (isIosDevice()) return 'IOS';
  return /Android/i.test(navigator.userAgent) ? 'ANDROID' : 'DESKTOP';
};

export const isEmbeddedBrowser = () =>
  /FBAN|FBAV|Instagram|Line\/|; wv\)|\bwv\b/i.test(navigator.userAgent);

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
  standalone.value = isPwaStandalone();
  window
    .matchMedia('(display-mode: standalone)')
    .addEventListener?.('change', () => {
      standalone.value = isPwaStandalone();
    });
  window.addEventListener('beforeinstallprompt', handleInstallPrompt);
  window.addEventListener('appinstalled', handleInstalled);
};

export const usePwaInstallation = () => {
  initializePwaInstallation();

  const validateManifest = async () => {
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

  const checkInstallability = () => {
    if (!checking) {
      checking = validateManifest().finally(() => {
        checking = null;
      });
    }
    return checking;
  };

  const status = computed(() => {
    if (installed.value || standalone.value) return 'installed';

    const hasManifest = Boolean(document.querySelector('link[rel="manifest"]'));
    if (!window.isSecureContext || !hasManifest) return 'unsupported';
    if (['manifest_error', 'icon_error'].includes(manifestStatus.value))
      return manifestStatus.value;
    if (isEmbeddedBrowser()) return 'embedded_instructions';
    if (installPrompt.value) return 'available';
    if (isIosDevice()) return 'ios_instructions';
    return 'unavailable';
  });

  const promptInstall = async () => {
    const prompt = installPrompt.value;
    if (!prompt || busy.value || status.value !== 'available')
      return { outcome: 'unavailable' };
    // Consume before awaiting. A new event must survive this prompt's result.
    installPrompt.value = null;
    busy.value = true;
    try {
      await prompt.prompt();
      return await prompt.userChoice;
    } finally {
      busy.value = false;
    }
  };

  return { status, busy, promptInstall, checkInstallability };
};
