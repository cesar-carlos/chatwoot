import { computed } from 'vue';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { useTrack } from 'dashboard/composables';
import { MESSAGE_SEARCH_EVENTS } from 'dashboard/helper/AnalyticsHelper/events';

export function useConversationMessageSearchPanel() {
  const { uiSettings, updateUISettings } = useUISettings();

  const isOpen = computed(() =>
    Boolean(uiSettings.value.is_message_search_panel_open)
  );

  const open = () => {
    updateUISettings({
      is_message_search_panel_open: true,
      is_contact_sidebar_open: false,
      is_copilot_panel_open: false,
    });
    useTrack(MESSAGE_SEARCH_EVENTS.OPENED);
  };

  const close = () => {
    updateUISettings({ is_message_search_panel_open: false });
  };

  const toggle = () => {
    if (isOpen.value) {
      close();
    } else {
      open();
    }
  };

  return {
    isOpen,
    open,
    close,
    toggle,
  };
}
