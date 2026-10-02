require 'rails_helper'

RSpec.describe Custom::Notification::TeamAssignmentTransition do
  let(:account) { create(:account) }
  let(:team) { create(:team, account: account, allow_auto_assign: false) }
  let(:user) { create(:user, account: account) }
  let(:conversation) { create(:conversation, account: account, team: team) }
  let(:revision) { described_class.state(conversation)['revision'] }

  before do
    team.members << user
    user.notification_settings.find_by!(account: account).update!(selected_push_flags: ['push_team_conversation_assignment'])
  end

  def deliver
    described_class.deliver(conversation: conversation, user: user, revision: revision) do
      NotificationBuilder.new(notification_type: 'team_conversation_assignment', user: user, account: account,
                              primary_actor: conversation).perform
    end
  end

  it 'persists the receipt atomically and does not recreate a notification even after history cleanup' do
    expect { deliver }.to change { user.notifications.team_conversation_assignment.count }.by(1)
    user.notifications.team_conversation_assignment.destroy_all
    expect { deliver }.not_to change(Notification, :count)
    expect(described_class.state(conversation.reload)['delivered_user_ids']).to eq([user.id])
  end

  it 'allows a new legitimate transition on the same conversation' do
    deliver
    previous_revision = revision
    conversation.update!(assignee: user)
    conversation.update!(assignee: nil)
    expect(described_class.state(conversation)['revision']).not_to eq(previous_revision)
    fresh_revision = described_class.state(conversation)['revision']
    expect do
      described_class.deliver(conversation: conversation, user: user, revision: fresh_revision) do
        NotificationBuilder.new(notification_type: 'team_conversation_assignment', user: user, account: account,
                                primary_actor: conversation).perform
      end
    end.to change { user.notifications.team_conversation_assignment.count }.by(1)
  end

  it 'rolls back the receipt and notification if creation fails, allowing a later job retry' do
    expect do
      described_class.deliver(conversation: conversation, user: user, revision: revision) do
        create(:notification, notification_type: :team_conversation_assignment, user: user, account: account, primary_actor: conversation)
        raise 'creation failed'
      end
    end.to raise_error('creation failed')
    expect(user.notifications.team_conversation_assignment).to be_empty
    expect(described_class.state(conversation.reload)['delivered_user_ids']).to be_empty
    expect { deliver }.to change { user.notifications.team_conversation_assignment.count }.by(1)
  end

  it 'does not record a receipt when the member is not eligible' do
    user.notification_settings.find_by!(account: account).update!(selected_email_flags: [], selected_push_flags: [])
    deliver
    expect(described_class.state(conversation.reload)['delivered_user_ids']).to be_empty
  end

  it 'preserves the protected state across stale additional-attribute writes' do
    stale = Conversation.find(conversation.id)
    deliver
    stale.update!(additional_attributes: { 'client_attribute' => 'value', described_class::ATTRIBUTE_KEY => { 'revision' => 'forged' } })
    expect(described_class.state(stale)).to include('revision' => revision, 'delivered_user_ids' => [user.id])
    expect(stale.additional_attributes['client_attribute']).to eq('value')
  end

  it 'does not rotate the revision for ordinary messages, reads or status changes' do
    original_revision = revision
    conversation.update!(agent_last_seen_at: Time.current, status: :resolved)
    expect(described_class.state(conversation)['revision']).to eq(original_revision)
  end

  it 'does not trust a forged state on initial conversation creation' do
    actor = create(:conversation, account: account, additional_attributes: { described_class::ATTRIBUTE_KEY => { 'revision' => 'forged' } })
    expect(described_class.state(actor)['revision']).not_to eq('forged')
  end
end
