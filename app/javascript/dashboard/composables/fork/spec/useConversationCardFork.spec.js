import { ref } from 'vue';
import { useConversationCardFork } from '../useConversationCardFork';

describe('useConversationCardFork', () => {
  const buildFork = ({
    assignee = null,
    team = null,
    canAssignToMe = true,
    currentUser = { id: 1, name: 'Agent', email: 'a@b.com' },
    isAssignPending = false,
  } = {}) => {
    const emit = vi.fn();
    const chat = ref({ id: 99, unread_count: 0 });
    const chatMetadata = ref({ assignee, team });

    const fork = useConversationCardFork({
      chat,
      chatMetadata,
      canAssignToMe: ref(canAssignToMe),
      currentUser: ref(currentUser),
      isAssignPending: ref(isAssignPending),
      emit,
    });

    return { ...fork, emit, chat, chatMetadata };
  };

  it('shows the fast-assign button for unassigned conversations', () => {
    const { showAssignmentButton } = buildFork();
    expect(showAssignmentButton.value).toBe(true);
  });

  it('hides the button when the conversation is assigned', () => {
    const { showAssignmentButton } = buildFork({ assignee: { id: 7 } });
    expect(showAssignmentButton.value).toBe(false);
  });

  it('hides the button when the user cannot assign to self', () => {
    const { showAssignmentButton } = buildFork({ canAssignToMe: false });
    expect(showAssignmentButton.value).toBe(false);
  });

  it('treats empty assignee objects as unassigned', () => {
    const { showAssignmentButton } = buildFork({ assignee: {} });
    expect(showAssignmentButton.value).toBe(true);
  });

  it('reserves preview padding when the button is visible', () => {
    const { messagePreviewPaddingClass } = buildFork();
    expect(messagePreviewPaddingClass.value).toBe('ltr:pr-24 rtl:pl-24');
  });

  it('applies consistent bottom padding on conversation cards', () => {
    const { cardBottomPaddingClass } = buildFork();
    expect(cardBottomPaddingClass).toBe('pb-2.5');
  });

  it('keeps bottom padding when the button is hidden', () => {
    const { cardBottomPaddingClass } = buildFork({ assignee: { id: 7 } });
    expect(cardBottomPaddingClass).toBe('pb-2.5');
  });

  it('emits assignAgent with the current user payload', () => {
    const { fastAssign, emit } = buildFork();
    const event = { stopPropagation: vi.fn() };

    fastAssign(event);

    expect(event.stopPropagation).toHaveBeenCalled();
    expect(emit).toHaveBeenCalledWith(
      'assignAgent',
      {
        id: 1,
        name: 'Agent',
        email: 'a@b.com',
        avatar_url: undefined,
      },
      [99]
    );
  });

  it('does not emit when assignment is already pending', () => {
    const { fastAssign, emit } = buildFork({ isAssignPending: true });
    const event = { stopPropagation: vi.fn() };

    fastAssign(event);

    expect(emit).not.toHaveBeenCalled();
  });

  it('exposes team meta when conversation has a team', () => {
    const { team, hasTeam } = buildFork({
      team: { id: 3, name: 'vendas' },
    });

    expect(hasTeam.value).toBe(true);
    expect(team.value).toEqual({ id: 3, name: 'vendas' });
  });

  it('reports no team when meta.team is missing', () => {
    const { hasTeam, team } = buildFork();

    expect(hasTeam.value).toBe(false);
    expect(team.value).toBeNull();
  });
});
