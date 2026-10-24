import { mount } from '@vue/test-utils';
import WebcamCaptureView from './WebcamCaptureView.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

const defineVideoSize = (video, width, height) => {
  Object.defineProperty(video, 'videoWidth', {
    configurable: true,
    value: width,
  });
  Object.defineProperty(video, 'videoHeight', {
    configurable: true,
    value: height,
  });
};

describe('WebcamCaptureView', () => {
  it('shows the whole frame and does not submit the dialog form', () => {
    const wrapper = mount(WebcamCaptureView, {
      props: { stream: {}, isVideoReady: true },
    });

    expect(wrapper.get('video').classes()).toContain('object-contain');
    expect(wrapper.get('button').attributes('type')).toBe('button');
    wrapper.unmount();
  });

  it('waits for a presented frame before enabling capture', async () => {
    const wrapper = mount(WebcamCaptureView, {
      props: { stream: {}, isVideoReady: false },
    });
    const video = wrapper.get('video').element;
    defineVideoSize(video, 1280, 720);

    let presentFrame = null;
    video.requestVideoFrameCallback = callback => {
      presentFrame = callback;
      return 7;
    };
    video.cancelVideoFrameCallback = vi.fn();

    await wrapper.get('video').trigger('loadeddata');
    expect(wrapper.emitted('videoReady')).toBeUndefined();

    presentFrame();
    expect(wrapper.emitted('videoReady')).toEqual([[true]]);
    wrapper.unmount();
  });

  it('enables capture from loadeddata when the browser has no frame callback', async () => {
    const wrapper = mount(WebcamCaptureView, {
      props: { stream: {} },
    });
    const video = wrapper.get('video').element;
    defineVideoSize(video, 640, 480);
    video.requestVideoFrameCallback = undefined;

    await wrapper.get('video').trigger('loadeddata');

    expect(wrapper.emitted('videoReady')).toEqual([[true]]);
    wrapper.unmount();
  });
});
