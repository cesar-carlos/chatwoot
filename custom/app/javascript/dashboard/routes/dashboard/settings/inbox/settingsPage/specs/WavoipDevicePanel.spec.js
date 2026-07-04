import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { flushPromises } from '@vue/test-utils';
import { mount } from '@vue/test-utils';
import { createStore } from 'vuex';

const useAlert = vi.fn();

vi.mock('dashboard/composables', () => ({
  useAlert: (...args) => useAlert(...args),
}));

const getWavoipDeviceStatus = vi.fn();
const getWavoipQr = vi.fn();
const postWavoipLogout = vi.fn();

vi.mock('dashboard/api/inboxes', () => ({
  default: {
    getWavoipDeviceStatus: (...args) => getWavoipDeviceStatus(...args),
    getWavoipQr: (...args) => getWavoipQr(...args),
    postWavoipLogout: (...args) => postWavoipLogout(...args),
  },
}));

const wakeUpInboxDevice = vi.fn();
const disconnectInbox = vi.fn();
const connectInbox = vi.fn();

vi.mock('customDashboard/composables/wavoip/useWavoipConnection', () => ({
  useWavoipConnection: () => ({
    wakeUpInboxDevice: (...args) => wakeUpInboxDevice(...args),
    disconnectInbox: (...args) => disconnectInbox(...args),
    connectInbox: (...args) => connectInbox(...args),
  }),
}));

const activeCallsRef = { value: 0 };
const numChannelsRef = { value: null };

vi.mock('customDashboard/lib/wavoip/wavoipDeviceStatus', () => ({
  hasWavoipDeviceActiveCalls: () => activeCallsRef.value > 0,
  getWavoipDeviceStatus: () => ({
    whatsAppStatus: { value: 'open' },
    connectionStatus: { value: 'connected' },
    activeCalls: activeCallsRef,
    numChannels: numChannelsRef,
    isRestricted: { value: false },
    restrictedUntil: { value: null },
  }),
  useWavoipDeviceStatus: () => ({
    whatsAppStatus: { value: null },
    activeCalls: activeCallsRef,
    numChannels: numChannelsRef,
    connectionStatus: { value: null },
    isRestricted: { value: false },
    restrictedUntil: { value: null },
  }),
}));

const getWavoipClientEntry = vi.fn();

vi.mock('customDashboard/lib/wavoip/wavoipClientRegistry', () => ({
  getWavoipClientEntry: (...args) => getWavoipClientEntry(...args),
}));

import WavoipDevicePanel from '../WavoipDevicePanel.vue';

describe('WavoipDevicePanel', () => {
  let store;

  beforeEach(() => {
    getWavoipDeviceStatus.mockResolvedValue({ data: { live: true } });
    getWavoipQr.mockReset().mockResolvedValue({});
    postWavoipLogout.mockReset().mockResolvedValue({});
    wakeUpInboxDevice.mockReset().mockResolvedValue(true);
    disconnectInbox.mockReset().mockResolvedValue();
    connectInbox.mockReset().mockResolvedValue({});
    getWavoipClientEntry.mockReset().mockReturnValue(undefined);
    activeCallsRef.value = 0;
    numChannelsRef.value = null;
    useAlert.mockReset();
    store = createStore({
      actions: {
        'inboxes/fetchInboxItem': vi.fn().mockResolvedValue({}),
      },
    });
    vi.useFakeTimers();
  });

  afterEach(() => {
    vi.useRealTimers();
    vi.restoreAllMocks();
  });

  const mountPanel = providerConfig =>
    mount(WavoipDevicePanel, {
      global: {
        plugins: [store],
        mocks: {
          $t: key => key,
        },
        stubs: {
          NextButton: true,
          Spinner: true,
          WavoipQrScanModal: true,
          Dialog: {
            template: '<div class="dialog-stub"><slot /><slot name="footer" /></div>',
            props: [
              'title',
              'description',
              'confirmButtonLabel',
              'isLoading',
              'type',
            ],
            emits: ['confirm', 'close'],
            methods: {
              open() {},
              close() {},
            },
          },
        },
      },
      props: {
        inbox: {
          id: 3,
          phone_number: '+15551234567',
          provider_config: providerConfig,
        },
      },
    });

  it('does not start polling on mount when the device is already connected', async () => {
    const setIntervalSpy = vi.spyOn(global, 'setInterval');

    mountPanel({ device_status: 'open' });
    await flushPromises();

    expect(setIntervalSpy).not.toHaveBeenCalled();
  });

  it('starts polling on mount when the device is not connected', async () => {
    const setIntervalSpy = vi.spyOn(global, 'setInterval');

    mountPanel({ device_status: 'connecting' });
    await flushPromises();

    expect(setIntervalSpy).toHaveBeenCalled();
  });

  it('wakes the device via the SDK when clicking "Wake up" (not just a REST status check)', async () => {
    const wrapper = mountPanel({ device_status: 'hibernating' });
    await flushPromises();

    const wakeUpButton = wrapper
      .findAll('next-button-stub')
      .find(
        button =>
          button.attributes('label') ===
          'INBOX_MGMT.WAVOIP_CALL.DEVICE_STATUS.WAKE_UP'
      );

    expect(wakeUpButton).toBeTruthy();
    getWavoipDeviceStatus.mockClear();

    await wakeUpButton.trigger('click');
    await flushPromises();

    expect(wakeUpInboxDevice).toHaveBeenCalledWith(3);
    // Wake-up still re-checks live status afterwards so the UI reflects the
    // outcome without waiting for the next poll.
    expect(getWavoipDeviceStatus).toHaveBeenCalledWith(
      3,
      expect.objectContaining({ force: true })
    );
  });

  it('keeps the SDK connection open after wake-up for live device stats', async () => {
    getWavoipClientEntry.mockReturnValue(undefined);
    const wrapper = mountPanel({ device_status: 'hibernating' });
    await flushPromises();

    const wakeUpButton = wrapper
      .findAll('next-button-stub')
      .find(
        button =>
          button.attributes('label') ===
          'INBOX_MGMT.WAVOIP_CALL.DEVICE_STATUS.WAKE_UP'
      );

    await wakeUpButton.trigger('click');
    await flushPromises();

    expect(disconnectInbox).not.toHaveBeenCalled();
  });

  it('disconnects the panel SDK connection on unmount', async () => {
    getWavoipClientEntry.mockReturnValue(undefined);
    connectInbox.mockResolvedValue({});
    const wrapper = mountPanel({ device_status: 'open' });
    await flushPromises();

    expect(connectInbox).toHaveBeenCalledWith(3);

    wrapper.unmount();
    await flushPromises();

    expect(disconnectInbox).toHaveBeenCalledWith(3);
  });

  it('surfaces an error instead of failing silently when clipboard copy is rejected', async () => {
    const writeText = vi
      .fn()
      .mockRejectedValue(new Error('Document is not focused'));
    Object.assign(navigator, { clipboard: { writeText } });

    const wrapper = mountPanel({ device_status: 'open' });
    await flushPromises();

    const copyButton = wrapper
      .findAll('next-button-stub')
      .find(
        button =>
          button.attributes('label') ===
          'INBOX_MGMT.WAVOIP_CALL.DIAGNOSTICS.COPY'
      );

    await copyButton.trigger('click');
    await flushPromises();

    expect(writeText).toHaveBeenCalled();
    expect(useAlert).toHaveBeenCalledWith('Document is not focused');
  });

  it('blocks restart when the device has active calls', async () => {
    activeCallsRef.value = 2;
    const wrapper = mountPanel({ device_status: 'open' });
    await flushPromises();

    const restartButton = wrapper
      .findAll('next-button-stub')
      .find(
        button =>
          button.attributes('label') ===
          'INBOX_MGMT.WAVOIP_CALL.DEVICE_STATUS.RESTART'
      );

    expect(restartButton.attributes('disabled')).toBe('true');
  });

  it('opens a confirmation dialog instead of restarting immediately when clicking Restart', async () => {
    const wrapper = mountPanel({ device_status: 'open' });
    await flushPromises();

    const restartButton = wrapper
      .findAll('next-button-stub')
      .find(
        button =>
          button.attributes('label') ===
          'INBOX_MGMT.WAVOIP_CALL.DEVICE_STATUS.RESTART'
      );
    await restartButton.trigger('click');
    await flushPromises();

    // Clicking the button only opens the confirmation dialog — the actual
    // restart call must wait for an explicit confirm.
    expect(getWavoipQr).not.toHaveBeenCalled();
  });

  it('restarts the device only after the restart dialog is confirmed', async () => {
    const wrapper = mountPanel({ device_status: 'open' });
    await flushPromises();

    const restartDialog = wrapper.findComponent({ ref: 'restartDialogRef' });
    await restartDialog.vm.$emit('confirm');
    await flushPromises();

    expect(getWavoipQr).toHaveBeenCalledWith(3, { refresh: true });
  });

  it('opens a confirmation dialog instead of logging out immediately when clicking Logout', async () => {
    const wrapper = mountPanel({ device_status: 'open' });
    await flushPromises();

    const logoutButton = wrapper
      .findAll('next-button-stub')
      .find(
        button =>
          button.attributes('label') ===
          'INBOX_MGMT.WAVOIP_CALL.DEVICE_STATUS.LOGOUT'
      );
    await logoutButton.trigger('click');
    await flushPromises();

    expect(postWavoipLogout).not.toHaveBeenCalled();
  });

  it('logs out only after the logout dialog is confirmed', async () => {
    const wrapper = mountPanel({ device_status: 'open' });
    await flushPromises();

    const logoutDialog = wrapper.findComponent({ ref: 'logoutDialogRef' });
    await logoutDialog.vm.$emit('confirm');
    await flushPromises();

    expect(postWavoipLogout).toHaveBeenCalledWith(3);
  });

  it('does not open the logout dialog (and re-opens QR instead) when the device is disconnected', async () => {
    const wrapper = mountPanel({ device_status: 'close' });
    await flushPromises();

    const logoutButton = wrapper
      .findAll('next-button-stub')
      .find(
        button =>
          button.attributes('label') ===
          'INBOX_MGMT.WAVOIP_CALL.DEVICE_STATUS.LOGOUT'
      );

    expect(logoutButton).toBeFalsy();
  });
});
