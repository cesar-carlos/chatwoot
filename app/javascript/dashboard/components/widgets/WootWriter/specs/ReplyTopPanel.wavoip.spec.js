import { describe, expect, it, vi } from 'vitest';
import { mount } from '@vue/test-utils';
import { REPLY_EDITOR_MODES } from '../constants';
import ReplyTopPanel from '../ReplyTopPanel.vue';

vi.mock('dashboard/composables/useKeyboardEvents', () => ({
  useKeyboardEvents: vi.fn(),
}));

vi.mock('dashboard/composables/useCaptain', () => ({
  useCaptain: () => ({ captainTasksEnabled: false }),
}));

describe('ReplyTopPanel Wavoip voice-only inbox', () => {
  const mountPanel = props =>
    mount(ReplyTopPanel, {
      props: {
        mode: REPLY_EDITOR_MODES.NOTE,
        conversationId: 1,
        isReplyRestricted: true,
        ...props,
      },
      global: {
        mocks: {
          $t: key => key,
        },
        stubs: {
          EditorModeToggle: {
            template: '<div data-testid="editor-mode-toggle" />',
          },
          NextButton: true,
          CopilotMenuBar: true,
        },
      },
    });

  it('hides reply toggle and shows private note label for voice-only inboxes', () => {
    const wrapper = mountPanel({ voiceOnlyInbox: true });

    expect(wrapper.find('[data-testid="editor-mode-toggle"]').exists()).toBe(
      false
    );
    expect(wrapper.text()).toContain('CONVERSATION.REPLYBOX.PRIVATE_NOTE');
  });

  it('shows reply toggle for regular restricted inboxes', () => {
    const wrapper = mountPanel({ voiceOnlyInbox: false });

    expect(wrapper.find('[data-testid="editor-mode-toggle"]').exists()).toBe(
      true
    );
  });
});
