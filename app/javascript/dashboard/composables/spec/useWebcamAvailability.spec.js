import { defineComponent, h } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import { useWebcamAvailability } from '../useWebcamAvailability';

const mountAvailability = () => {
  let composable;
  const wrapper = mount(
    defineComponent({
      setup() {
        composable = useWebcamAvailability();
        return () => h('div');
      },
    })
  );

  return { wrapper, ...composable };
};

describe('useWebcamAvailability', () => {
  let enumerateDevices;
  let addEventListener;
  let removeEventListener;
  let query;

  beforeEach(() => {
    enumerateDevices = vi.fn().mockResolvedValue([
      { kind: 'audioinput', label: '' },
      { kind: 'videoinput', label: '' },
    ]);
    addEventListener = vi.fn();
    removeEventListener = vi.fn();
    query = vi.fn().mockResolvedValue({ state: 'prompt', onchange: null });

    Object.defineProperty(window, 'isSecureContext', {
      configurable: true,
      value: true,
    });
    Object.defineProperty(navigator, 'mediaDevices', {
      configurable: true,
      value: { enumerateDevices, addEventListener, removeEventListener },
    });
    Object.defineProperty(navigator, 'permissions', {
      configurable: true,
      value: { query },
    });
  });

  it('shows the button when a videoinput exists and does not request the camera', async () => {
    const { wrapper, hasWebcam, isCameraDenied } = mountAvailability();
    await flushPromises();

    expect(hasWebcam.value).toBe(true);
    expect(isCameraDenied.value).toBe(false);
    expect(enumerateDevices).toHaveBeenCalledTimes(1);
    expect(navigator.mediaDevices.getUserMedia).toBeUndefined();
    wrapper.unmount();
  });

  it('hides the button when the page is not a secure context', async () => {
    Object.defineProperty(window, 'isSecureContext', {
      configurable: true,
      value: false,
    });
    const { wrapper, hasWebcam } = mountAvailability();
    await flushPromises();

    expect(hasWebcam.value).toBe(false);
    expect(enumerateDevices).not.toHaveBeenCalled();
    wrapper.unmount();
  });

  it('hides the button when enumerateDevices fails or finds no camera', async () => {
    enumerateDevices.mockResolvedValue([{ kind: 'audioinput' }]);
    const { wrapper, hasWebcam, refreshDevices } = mountAvailability();
    await flushPromises();
    expect(hasWebcam.value).toBe(false);

    enumerateDevices.mockRejectedValue(new Error('blocked'));
    await refreshDevices();
    expect(hasWebcam.value).toBe(false);
    wrapper.unmount();
  });

  it('updates when a camera is plugged in', async () => {
    enumerateDevices.mockResolvedValue([]);
    const { wrapper, hasWebcam } = mountAvailability();
    await flushPromises();
    expect(hasWebcam.value).toBe(false);

    const handler = addEventListener.mock.calls.find(
      call => call[0] === 'devicechange'
    )[1];
    enumerateDevices.mockResolvedValue([{ kind: 'videoinput' }]);
    await handler();

    expect(hasWebcam.value).toBe(true);
    wrapper.unmount();
    expect(removeEventListener).toHaveBeenCalledWith('devicechange', handler);
  });

  it('marks a denied camera without hiding the button', async () => {
    const status = { state: 'denied', onchange: null };
    query.mockResolvedValue(status);
    const { wrapper, hasWebcam, isCameraDenied } = mountAvailability();
    await flushPromises();

    expect(hasWebcam.value).toBe(true);
    expect(isCameraDenied.value).toBe(true);

    status.state = 'granted';
    status.onchange();
    expect(isCameraDenied.value).toBe(false);
    wrapper.unmount();
    expect(status.onchange).toBeNull();
  });

  it('keeps the button usable when the permissions API rejects camera', async () => {
    query.mockRejectedValue(new TypeError('name not supported'));
    const { wrapper, hasWebcam, isCameraDenied } = mountAvailability();
    await flushPromises();

    expect(hasWebcam.value).toBe(true);
    expect(isCameraDenied.value).toBe(false);
    wrapper.unmount();
  });

  it('keeps the button usable when permissions.query is missing', async () => {
    Object.defineProperty(navigator, 'permissions', {
      configurable: true,
      value: undefined,
    });
    const { wrapper, hasWebcam, isCameraDenied } = mountAvailability();
    await flushPromises();

    expect(hasWebcam.value).toBe(true);
    expect(isCameraDenied.value).toBe(false);
    wrapper.unmount();
  });
});
