require 'rails_helper'

RSpec.describe 'Concurrent team notification creation', type: :model do
  self.use_transactional_tests = false

  let(:account) { create(:account) }
  let(:team) { create(:team, account: account, allow_auto_assign: false) }
  let(:user) { create(:user, account: account) }
  let!(:conversation) { create(:conversation, account: account, team: team) }

  before do
    team.members << user
    user.notification_settings.find_by!(account: account).update!(selected_email_flags: [],
                                                                  selected_push_flags: ['push_team_conversation_assignment'])
  end

  after do
    # Associations are destroyed asynchronously; clear this example's notifications before deleting their owner.
    user.notifications.destroy_all
    account.destroy!
    user.destroy!
  end

  it 'serializes two workers processing the same transition through the PostgreSQL row lock' do
    revision = Custom::Notification::TeamAssignmentTransition.state(conversation)['revision']
    ready = Queue.new
    start = Queue.new
    workers = Array.new(2) do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          actor = Conversation.find(conversation.id)
          ready << true
          start.pop
          Custom::Notification::TeamAssignmentTransition.deliver(conversation: actor, user: user, revision: revision) do
            NotificationBuilder.new(notification_type: 'team_conversation_assignment', user: user,
                                    account: account, primary_actor: actor).perform
          end
        end
      end
    end
    2.times { ready.pop }
    2.times { start << true }
    workers.each(&:value)
    expect(user.notifications.team_conversation_assignment.count).to eq(1)
    expect(Custom::Notification::TeamAssignmentTransition.state(conversation.reload)['delivered_user_ids']).to eq([user.id])
  end
end
