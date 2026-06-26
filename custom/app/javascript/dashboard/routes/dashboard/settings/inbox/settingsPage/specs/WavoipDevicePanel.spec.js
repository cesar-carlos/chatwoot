import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { flushPromises } from '@vue/test-utils';
import { mount } from '@vue/test-utils';
import { createStore } from 'vuex';

vi.mock('dashboard/composables', () => ({
  useAlert: vi.fn(),
}));

const getWavoipDeviceStatus = vi.fn();

vi.mock('dashboard/api/inboxes', () => ({
  default: {
    getWavoipDeviceStatus: (...args) => getWavoipDeviceStatus(...args),
  },
}));

import WavoipDevicePanel from '../WavoipDevicePanel.vue';

describe('WavoipDevicePanel', () => {
  let store;

  beforeEach(() => {
    getWavoipDeviceStatus.mockResolvedValue({ data: { live: true } });
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
          SettingsFieldSection: true,
          NextButton: true,
          Spinner: true,
          WavoipQrScanModal: true,
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
});
