import { beforeEach, describe, expect, it, vi } from 'vitest';
import { VOICE_CALL_OUTBOUND_INIT_STATUS } from 'dashboard/components-next/message/constants';
import {
  applyOutboundAnswer,
  configureWebRtcCallsAPI,
  configureWebRtcTranslate,
  cleanupWebRtcSession,
  sendWebRtcTerminateBeacon,
  useWebRtcCallSession,
} from '../useWebRtcCallSession';

const mockStream = {
  getTracks: () => [{ stop: vi.fn() }],
  getAudioTracks: () => [],
};

const mockPc = {
  setRemoteDescription: vi.fn().mockResolvedValue(undefined),
  createOffer: vi.fn().mockResolvedValue({ type: 'offer', sdp: 'local-offer' }),
  setLocalDescription: vi.fn().mockResolvedValue(undefined),
  localDescription: { sdp: 'local-offer' },
  close: vi.fn(),
  getSenders: vi.fn(() => []),
  addTrack: vi.fn(),
  addEventListener: vi.fn(),
  iceGatheringState: 'complete',
  connectionState: 'connected',
  ontrack: null,
};

vi.stubGlobal('RTCPeerConnection', vi.fn(() => mockPc));
vi.stubGlobal('MediaStream', vi.fn(() => mockStream));
vi.stubGlobal('MediaRecorder', { isTypeSupported: () => false });

describe('useWebRtcCallSession', () => {
  const mockApi = {
    initiate: vi.fn(),
    accept: vi.fn(),
    reject: vi.fn(),
    terminate: vi.fn(),
    uploadRecording: vi.fn(),
    show: vi.fn(),
  };

  beforeEach(() => {
    vi.clearAllMocks();
    cleanupWebRtcSession();
    configureWebRtcCallsAPI(mockApi);
    configureWebRtcTranslate(key => key);

    Object.defineProperty(global, 'navigator', {
      value: {
        mediaDevices: {
          getUserMedia: vi.fn().mockResolvedValue(mockStream),
        },
      },
      writable: true,
      configurable: true,
    });

    Object.defineProperty(window, 'location', {
      value: { pathname: '/app/accounts/1/conversations/2' },
      writable: true,
      configurable: true,
    });

    document.cookie = `cw_d_session_info=${encodeURIComponent(
      JSON.stringify({
        'access-token': 'token',
        client: 'client',
        uid: 'uid@example.com',
        expiry: '9999999999',
      })
    )}`;

    vi.stubGlobal('fetch', vi.fn().mockResolvedValue({ ok: true }));
  });

  it('ignores outbound SDP answers for foreign call ids', async () => {
    mockApi.initiate.mockResolvedValue({ id: 99 });
    await useWebRtcCallSession().initiateOutboundCall(1);

    await applyOutboundAnswer(100, 'foreign-sdp');

    expect(mockPc.setRemoteDescription).not.toHaveBeenCalled();
  });

  it('applies outbound SDP answer for the active call', async () => {
    mockApi.initiate.mockResolvedValue({ id: 99 });
    await useWebRtcCallSession().initiateOutboundCall(1);

    await applyOutboundAnswer(99, 'matching-sdp');

    expect(mockPc.setRemoteDescription).toHaveBeenCalledWith({
      type: 'answer',
      sdp: 'matching-sdp',
    });
  });

  it('maps permission 422 to structured outbound status', async () => {
    mockApi.initiate.mockRejectedValue({
      response: {
        status: 422,
        data: { status: VOICE_CALL_OUTBOUND_INIT_STATUS.PERMISSION_REQUESTED },
      },
    });

    const session = useWebRtcCallSession();
    const result = await session.initiateOutboundCall(1);

    expect(result).toEqual({
      status: VOICE_CALL_OUTBOUND_INIT_STATUS.PERMISSION_REQUESTED,
    });
  });

  it('sends terminate beacon with auth headers on page hide path', async () => {
    mockApi.initiate.mockResolvedValue({ id: 42 });

    const session = useWebRtcCallSession();
    await session.initiateOutboundCall(1);
    sendWebRtcTerminateBeacon();

    expect(fetch).toHaveBeenCalledWith(
      '/api/v1/accounts/1/whatsapp_calls/42/terminate',
      expect.objectContaining({
        method: 'POST',
        keepalive: true,
      })
    );
  });
});
