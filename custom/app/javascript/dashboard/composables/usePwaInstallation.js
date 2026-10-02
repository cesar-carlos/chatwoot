import { computed, ref } from 'vue';
import { isPwaStandalone } from 'customDashboard/helper/pushHelper';

const installPrompt = ref(null);
const installed = ref(false);
const manifestStatus = ref(null);
const busy = ref(false);
const standalone = ref(false);
const checking = ref(false);
let pendingValidation;
let initialized = false;
export const PWA_VALIDATION_TIMEOUT_MS = 10000;

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

    const controller = new AbortController();
    const timeout = setTimeout(
      () => controller.abort(),
      PWA_VALIDATION_TIMEOUT_MS
    );
    try {
      const response = await fetch(manifestLink.href, {
        signal: controller.signal,
      });
      if (!response.ok) {
        manifestStatus.value =
          response.status >= 500 ? 'connection_error' : 'manifest_error';
        return;
      }
      let manifest;
      try {
        manifest = await response.json();
      } catch (error) {
        if (controller.signal.aborted)
          manifestStatus.value = 'connection_timeout';
        else
          manifestStatus.value =
            error instanceof SyntaxError
              ? 'manifest_error'
              : 'connection_error';
        return;
      }
      if (
        !manifest ||
        !(manifest.name || manifest.short_name) ||
        !manifest.start_url ||
        !['standalone', 'fullscreen', 'minimal-ui'].includes(manifest.display)
      ) {
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
      const responses = await Promise.all(
        iconUrls.map(url => fetch(url.href, { signal: controller.signal }))
      );
      if (responses.some(icon => icon.status >= 500))
        manifestStatus.value = 'connection_error';
      else
        manifestStatus.value = responses.every(
          icon =>
            icon.ok && icon.headers.get('content-type')?.startsWith('image/png')
        )
          ? 'valid'
          : 'icon_error';
    } catch (error) {
      manifestStatus.value = controller.signal.aborted
        ? 'connection_timeout'
        : 'connection_error';
    } finally {
      clearTimeout(timeout);
      // Stop any remaining icon download after a parallel fetch fails.
      controller.abort();
    }
  };

  const checkInstallability = () => {
    if (!pendingValidation) {
      checking.value = true;
      pendingValidation = validateManifest().finally(() => {
        pendingValidation = null;
        checking.value = false;
      });
    }
    return pendingValidation;
  };

  const status = computed(() => {
    if (installed.value || standalone.value) return 'installed';

    const hasManifest = Boolean(document.querySelector('link[rel="manifest"]'));
    if (!window.isSecureContext || !hasManifest) return 'unsupported';
    if (checking.value) return 'checking';
    if (
      [
        'manifest_error',
        'icon_error',
        'connection_error',
        'connection_timeout',
      ].includes(manifestStatus.value)
    )
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
