import { defineComponent, h } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import {
  primeWebcamStream,
  releasePrimedWebcamStream,
  useWebcamCapture,
} from '../useWebcamCapture';

vi.mock('widget/helpers/uuid', () => ({
  default: () => 'test-uuid',
}));

const mountCapture = () => {
  let composable;
  const wrapper = mount(
    defineComponent({
      setup() {
        composable = useWebcamCapture();
        return () => h('div');
      },
    })
  );

  return { wrapper, ...composable };
};

const mediaStream = tracks => ({
  getTracks: () => tracks,
});

describe('useWebcamCapture', () => {
  const originalCreateElement = document.createElement.bind(document);
  const originalCreateObjectURL = Object.getOwnPropertyDescriptor(
    URL,
    'createObjectURL'
  );
  const originalRevokeObjectURL = Object.getOwnPropertyDescriptor(
    URL,
    'revokeObjectURL'
  );
  let getUserMedia;
  let canvas;
  let drawImage;
  let toBlob;

  beforeEach(() => {
    drawImage = vi.fn();
    toBlob = vi.fn(callback => {
      callback(new Blob(['jpeg'], { type: 'image/jpeg' }));
    });
    canvas = {
      width: 0,
      height: 0,
      getContext: vi.fn(() => ({
        drawImage,
        imageSmoothingEnabled: false,
        imageSmoothingQuality: 'low',
      })),
      toBlob,
    };

    vi.spyOn(document, 'createElement').mockImplementation(tagName => {
      if (tagName === 'canvas') return canvas;
      return originalCreateElement(tagName);
    });
    Object.defineProperty(URL, 'createObjectURL', {
      configurable: true,
      writable: true,
      value: vi.fn(() => 'blob:preview'),
    });
    Object.defineProperty(URL, 'revokeObjectURL', {
      configurable: true,
      writable: true,
      value: vi.fn(),
    });

    getUserMedia = vi.fn();
    Object.defineProperty(window, 'isSecureContext', {
      configurable: true,
      value: true,
    });
    Object.defineProperty(navigator, 'mediaDevices', {
      configurable: true,
      value: { getUserMedia },
    });
  });

  afterEach(() => {
    releasePrimedWebcamStream();
    vi.restoreAllMocks();
    if (originalCreateObjectURL) {
      Object.defineProperty(URL, 'createObjectURL', originalCreateObjectURL);
    }
    if (originalRevokeObjectURL) {
      Object.defineProperty(URL, 'revokeObjectURL', originalRevokeObjectURL);
    }
  });

  it('adopts a stream primed in the click turn instead of requesting twice', async () => {
    const track = { stop: vi.fn() };
    getUserMedia.mockResolvedValue(mediaStream([track]));

    primeWebcamStream();
    const { wrapper, startStream, stream } = mountCapture();
    await startStream();

    expect(getUserMedia).toHaveBeenCalledTimes(1);
    expect(getUserMedia).toHaveBeenCalledWith({
      audio: false,
      video: {
        facingMode: { ideal: 'user' },
        width: { ideal: 1280 },
        height: { ideal: 720 },
      },
    });
    expect(stream.value.getTracks()).toEqual([track]);
    wrapper.unmount();
  });

  it('stops a primed stream that the dialog never adopts', async () => {
    const track = { stop: vi.fn() };
    let resolveStream;
    getUserMedia.mockImplementation(
      () =>
        new Promise(resolve => {
          resolveStream = resolve;
        })
    );

    primeWebcamStream();
    releasePrimedWebcamStream();
    resolveStream(mediaStream([track]));
    await flushPromises();

    expect(track.stop).toHaveBeenCalledTimes(1);
  });

  it('drops a stream that arrives after the dialog closed', async () => {
    const track = { stop: vi.fn() };
    let resolveStream;
    getUserMedia.mockImplementation(
      () =>
        new Promise(resolve => {
          resolveStream = resolve;
        })
    );

    const { wrapper, startStream, stopStream, stream } = mountCapture();
    const pending = startStream();
    stopStream();
    resolveStream(mediaStream([track]));
    await pending;

    expect(track.stop).toHaveBeenCalledTimes(1);
    expect(stream.value).toBeNull();
    wrapper.unmount();
  });

  it('maps a denied camera to the permission error and stops tracks', async () => {
    getUserMedia.mockRejectedValue(
      new DOMException('denied', 'NotAllowedError')
    );
    const { wrapper, startStream, error, isStarting } = mountCapture();

    await startStream();

    expect(error.value).toBe('PERMISSION');
    expect(isStarting.value).toBe(false);
    wrapper.unmount();
  });

  it('scales the longest edge to 1920 and names the jpeg with a uuid', async () => {
    const { wrapper, capturePhoto, capturedFile, error } = mountCapture();

    const file = await capturePhoto({ videoWidth: 3840, videoHeight: 2160 });

    expect(canvas.width).toBe(1920);
    expect(canvas.height).toBe(1080);
    expect(drawImage).toHaveBeenCalledWith(
      { videoWidth: 3840, videoHeight: 2160 },
      0,
      0,
      1920,
      1080
    );
    expect(file.name).toBe('webcam-test-uuid.jpg');
    expect(file.type).toBe('image/jpeg');
    expect(capturedFile.value).toBe(file);
    expect(error.value).toBeNull();
    wrapper.unmount();
  });

  it('keeps a frame that already fits inside 1920', async () => {
    const { wrapper, capturePhoto } = mountCapture();

    await capturePhoto({ videoWidth: 1280, videoHeight: 720 });

    expect(canvas.width).toBe(1280);
    expect(canvas.height).toBe(720);
    wrapper.unmount();
  });

  it('stops the camera when the jpeg blob is empty', async () => {
    const track = { stop: vi.fn() };
    toBlob.mockImplementation(callback => callback(null));
    const { wrapper, startStream, capturePhoto, error, stream } =
      mountCapture();
    getUserMedia.mockResolvedValue(mediaStream([track]));
    await startStream();

    const file = await capturePhoto({ videoWidth: 640, videoHeight: 480 });

    expect(file).toBeNull();
    expect(error.value).toBe('GENERIC');
    expect(track.stop).toHaveBeenCalledTimes(1);
    expect(stream.value).toBeNull();
    wrapper.unmount();
  });

  it('discards a blob that arrives after the dialog closed', async () => {
    let finishBlob;
    toBlob.mockImplementation(callback => {
      finishBlob = () => callback(new Blob(['jpeg'], { type: 'image/jpeg' }));
    });
    const { wrapper, capturePhoto, reset, capturedFile } = mountCapture();

    const pending = capturePhoto({ videoWidth: 640, videoHeight: 480 });
    reset();
    finishBlob();
    await pending;

    expect(capturedFile.value).toBeNull();
    expect(URL.createObjectURL).not.toHaveBeenCalled();
    wrapper.unmount();
  });

  it('stops the camera when the video has no dimensions', async () => {
    const track = { stop: vi.fn() };
    const { wrapper, startStream, capturePhoto, error } = mountCapture();
    getUserMedia.mockResolvedValue(mediaStream([track]));
    await startStream();

    await capturePhoto({ videoWidth: 0, videoHeight: 0 });

    expect(error.value).toBe('GENERIC');
    expect(track.stop).toHaveBeenCalledTimes(1);
    wrapper.unmount();
  });

  it('reports a generic error without calling getUserMedia outside a secure context', async () => {
    Object.defineProperty(window, 'isSecureContext', {
      configurable: true,
      value: false,
    });
    const { wrapper, startStream, error } = mountCapture();

    await expect(startStream()).resolves.toBeNull();
    expect(getUserMedia).not.toHaveBeenCalled();
    expect(error.value).toBe('GENERIC');
    wrapper.unmount();
  });
});
