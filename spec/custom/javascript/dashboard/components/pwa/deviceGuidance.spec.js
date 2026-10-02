import { mount, flushPromises } from '@vue/test-utils';
import { beforeEach, describe, expect, it, vi } from 'vitest';
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('shared/composables/useBranding', () => ({
  useBranding: () => ({ replaceInstallationName: value => value }),
}));
vi.mock('customDashboard/composables/usePushDevice', async () => {
  const { ref } = await import('vue');
  const device = {
    status: ref('subscribed'),
    permission: ref('granted'),
    reason: ref(null),
    activity: ref(null),
    subscribed: ref(true),
    endpoint: ref('https://push.example.test/device'),
    busy: ref(false),
    disabled: ref(false),
    activate: vi.fn(),
    deactivate: vi.fn(),
    refresh: vi.fn(),
  };
  return { device, usePushDevice: () => device };
});
import { device } from 'customDashboard/composables/usePushDevice';
import PwaDeviceSettings from 'customDashboard/components/pwa/PwaDeviceSettings.vue';

const render = props =>
  mount(PwaDeviceSettings, {
    props,
    global: {
      stubs: {
        FluentIcon: true,
        PwaInstallationCard: true,
        PushDeviceDiagnostics: true,
        Dialog: true,
        ToggleSwitch: true,
        Button: true,
      },
    },
  });

describe('device progress and event-selection guidance', () => {
  beforeEach(() => {
    device.subscribed.value = true;
    device.status.value = 'subscribed';
    device.activity.value = null;
    device.reason.value = null;
  });
  it('shows no-events guidance only after the account preferences have loaded', async () => {
    const wrapper = render({
      pushPreferencesReady: false,
      selectedPushFlags: [],
    });
    expect(wrapper.text()).not.toContain('PUSH_NO_EVENTS_HINT');
    await wrapper.setProps({ pushPreferencesReady: true });
    expect(wrapper.text()).toContain('PUSH_NO_EVENTS_HINT');
    expect(wrapper.get('a').attributes('href')).toBe(
      '#profile-settings-notification-events'
    );
    expect(device.activate).not.toHaveBeenCalled();
    await wrapper.setProps({
      selectedPushFlags: ['push_conversation_assignment'],
    });
    expect(wrapper.text()).not.toContain('PUSH_NO_EVENTS_HINT');
    wrapper.unmount();
  });
  it('hides the no-events notice during account switching, failures or saving', async () => {
    const wrapper = render({
      pushPreferencesReady: true,
      selectedPushFlags: [],
    });
    expect(wrapper.text()).toContain('PUSH_NO_EVENTS_HINT');
    await wrapper.setProps({ pushPreferencesReady: false });
    expect(wrapper.text()).not.toContain('PUSH_NO_EVENTS_HINT');
    await wrapper.setProps({ pushPreferencesReady: true });
    device.subscribed.value = false;
    await flushPromises();
    expect(wrapper.text()).not.toContain('PUSH_NO_EVENTS_HINT');
    wrapper.unmount();
  });
  it.each(['checking', 'activating', 'testing', 'deactivating'])(
    'labels %s accurately rather than using the global busy flag',
    async activity => {
      device.activity.value = activity;
      const wrapper = render({});
      expect(wrapper.text()).toContain(`PUSH_STATUS_${activity.toUpperCase()}`);
      wrapper.unmount();
    }
  );
  it.each(['insecure_context', 'unsupported_browser', 'missing_configuration'])(
    'shows actionable environment guidance for %s',
    reason => {
      device.status.value = 'unsupported';
      device.subscribed.value = false;
      device.reason.value = reason;
      const wrapper = render({});
      expect(wrapper.text()).toContain(`PUSH_STATUS_${reason.toUpperCase()}`);
      expect(wrapper.text()).not.toContain('PUSH_STATUS_DENIED');
      wrapper.unmount();
    }
  );
});
