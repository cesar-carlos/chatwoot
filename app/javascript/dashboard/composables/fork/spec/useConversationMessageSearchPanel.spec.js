import { ref } from 'vue';
import { useConversationMessageSearchPanel } from '../useConversationMessageSearchPanel';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { useTrack } from 'dashboard/composables';

vi.mock('dashboard/composables/useUISettings');
vi.mock('dashboard/composables', () => ({
  useTrack: vi.fn(),
}));

describe('useConversationMessageSearchPanel', () => {
  const setup = (isOpen = false) => {
    const uiSettings = ref({
      is_message_search_panel_open: isOpen,
      is_contact_sidebar_open: false,
      is_copilot_panel_open: false,
    });
    const updateUISettings = vi.fn(updates => {
      uiSettings.value = { ...uiSettings.value, ...updates };
    });

    useUISettings.mockReturnValue({ uiSettings, updateUISettings });

    return {
      panel: useConversationMessageSearchPanel(),
      updateUISettings,
      uiSettings,
    };
  };

  it('opens the panel and closes other sidepanels', () => {
    const { panel, updateUISettings } = setup(false);

    panel.open();

    expect(updateUISettings).toHaveBeenCalledWith({
      is_message_search_panel_open: true,
      is_contact_sidebar_open: false,
      is_copilot_panel_open: false,
    });
    expect(useTrack).toHaveBeenCalled();
  });

  it('closes the panel', () => {
    const { panel, updateUISettings } = setup(true);

    panel.close();

    expect(updateUISettings).toHaveBeenCalledWith({
      is_message_search_panel_open: false,
    });
  });

  it('toggles from closed to open', () => {
    const { panel, updateUISettings } = setup(false);

    panel.toggle();

    expect(updateUISettings).toHaveBeenCalledWith({
      is_message_search_panel_open: true,
      is_contact_sidebar_open: false,
      is_copilot_panel_open: false,
    });
  });

  it('toggles from open to closed', () => {
    const { panel, updateUISettings } = setup(true);

    panel.toggle();

    expect(updateUISettings).toHaveBeenCalledWith({
      is_message_search_panel_open: false,
    });
  });
});
