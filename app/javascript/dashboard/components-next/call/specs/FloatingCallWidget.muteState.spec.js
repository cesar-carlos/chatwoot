import { describe, expect, it, vi, beforeEach } from 'vitest';
import { mount } from '@vue/test-utils';
import { ref, computed } from 'vue';
import { createStore } from 'vuex';
import { createRouter, createWebHistory } from 'vue-router';
import { VOICE_CALL_PROVIDERS } from 'dashboard/helper/inbox';

const activeCall = ref(null);
const incomingCalls = ref([]);
const hasActiveCall = computed(() => !!activeCall.value);

vi.mock('dashboard/composables/useCallSession', () => ({
  useCallSession: () => ({
    activeCall,
    incomingCalls,
    hasActiveCall,
    isJoining: ref(false),
    joinCall: vi.fn(),
    endCall: vi.fn(),
    rejectIncomingCall: vi.fn(),
    dismissCall: vi.fn(),
    formattedCallDuration: ref('00:00'),
  }),
  isCallRingtoneSilenced: () => false,
}));

vi.mock('dashboard/composables/useCallRingtonePreference', () => ({
  useCallRingtonePreference: () => ({
    isRingtoneMuted: ref(false),
    initPreference: vi.fn(),
    toggleRingtoneMute: vi.fn(),
  }),
}));

vi.mock('dashboard/composables/useWhatsappCallSession', () => ({
  setWhatsappCallMuted: vi.fn(),
}));

const wavoipIsMuted = ref(false);
const setWavoipMuted = vi.fn(muted => {
  wavoipIsMuted.value = muted;
});

vi.mock('customDashboard/composables/wavoip/useWavoipActiveCall', () => ({
  useWavoipActiveCall: () => ({
    setMuted: setWavoipMuted,
    isMuted: wavoipIsMuted,
    mediaConnectionStatus: ref(null),
    callLegStatus: ref(null),
  }),
}));

vi.mock('customDashboard/lib/wavoip/wavoipDeviceStatus', () => ({
  getWavoipDeviceStatus: () => ({ connectionStatus: ref(null) }),
}));

vi.mock('dashboard/api/channel/voice/twilioVoiceClient', () => ({
  default: { setMuted: vi.fn() },
}));

// Import after mocks so Vitest hoists do not break module wiring.
import FloatingCallWidget from '../FloatingCallWidget.vue';

describe('FloatingCallWidget — mute state', () => {
  const store = createStore({
    getters: {
      getConversationById: () => () => null,
      'inboxes/getInbox': () => () => null,
    },
  });
  const router = createRouter({
    history: createWebHistory(),
    routes: [{ path: '/', component: { template: '<div />' } }],
  });

  beforeEach(() => {
    activeCall.value = null;
    incomingCalls.value = [];
    wavoipIsMuted.value = false;
    setWavoipMuted.mockClear();
  });

  const mountWidget = () =>
    mount(FloatingCallWidget, {
      global: { plugins: [store, router] },
    });

  it('reflects the Wavoip composable isMuted state directly, not a local copy', async () => {
    activeCall.value = {
      callSid: 'wavoip_call_1',
      provider: VOICE_CALL_PROVIDERS.WAVOIP,
      conversationId: 1,
      inboxId: 2,
    };
    const wrapper = mountWidget();

    // Something external changes the composable's mute state (e.g. a device
    // event) without going through this widget's own toggle button.
    wavoipIsMuted.value = true;
    await wrapper.vm.$nextTick();

    const callCard = wrapper.findComponent({ name: 'CallCard' });
    expect(callCard.props('isMuted')).toBe(true);
  });

  it('toggling mute for a Wavoip call delegates to the composable and stays in sync', async () => {
    activeCall.value = {
      callSid: 'wavoip_call_2',
      provider: VOICE_CALL_PROVIDERS.WAVOIP,
      conversationId: 1,
      inboxId: 2,
    };
    const wrapper = mountWidget();

    await wrapper.findComponent({ name: 'CallCard' }).vm.$emit('toggleMute');

    expect(setWavoipMuted).toHaveBeenCalledWith(true);
    await wrapper.vm.$nextTick();
    expect(wrapper.findComponent({ name: 'CallCard' }).props('isMuted')).toBe(
      true
    );
  });
});
