require 'rails_helper'

RSpec.describe NotificationListener do
  let(:listener) { described_class.instance }
  let(:account) { create(:account) }
  let(:team) { create(:team, account: account, allow_auto_assign: false) }
  let(:user) { create(:user, account: account) }
  let(:conversation) { create(:conversation, account: account, team: team) }
  let(:settings) { user.notification_settings.find_by!(account: account) }
  let(:notifications) { user.notifications.where(notification_type: :team_conversation_assignment) }

  before do
    team.members << user
    settings.update!(selected_email_flags: [], selected_push_flags: ['push_team_conversation_assignment'])
  end

  def dispatch(method, changes = {})
    attributes = conversation.reload.additional_attributes.deep_dup
    changes = { 'additional_attributes' => [nil, attributes] }.merge(changes)
    event = Events::Base.new("#{method}.changed", Time.current, conversation: conversation, changed_attributes: changes)
    listener.public_send(method, event)
  end

  it 'notifies an authorized team member with no individual assignee and captures the original team' do
    dispatch(:team_changed)
    expect(notifications.count).to eq(1)
    expect(notifications.last.meta['assignment_team_id']).to eq(team.id)
  end

  it 'supports popup-only opt-in scoped to the account' do
    settings.update!(selected_push_flags: [])
    user.update!(ui_settings: { 'popup_notification_flags_by_account' => { account.id.to_s => ['popup_team_conversation_assignment'] } })
    dispatch(:team_changed)
    expect(notifications.count).to eq(1)
    expect(enqueued_jobs.pluck(:job)).not_to include(Notification::PushNotificationJob, Notification::EmailNotificationJob)
  end

  it 'does not opt users into the new event by default' do
    settings.update!(selected_push_flags: [])
    dispatch(:team_changed)
    expect(notifications).to be_empty
  end

  it 'does not read popup opt-in from a different account' do
    settings.update!(selected_push_flags: [])
    user.update!(ui_settings: { 'popup_notification_flags_by_account' => { (account.id + 1).to_s => ['popup_team_conversation_assignment'] } })
    dispatch(:team_changed)
    expect(notifications).to be_empty
  end

  it 'does not notify nonmembers even if they are administrators or inbox members' do
    outsider = create(:user, :administrator, account: account)
    create(:inbox_member, user: outsider, inbox: conversation.inbox)
    outsider.notification_settings.find_by!(account: account).update!(selected_push_flags: ['push_team_conversation_assignment'])
    dispatch(:team_changed)
    expect(outsider.notifications).to be_empty
  end

  it 'does not notify a removed account member still present in the team' do
    user.account_users.find_by!(account: account).destroy!
    dispatch(:team_changed)
    expect(notifications).to be_empty
  end

  it 'respects custom-role conversation access and notification access' do
    role = create(:custom_role, account: account, permissions: %w[inbox_view_manage conversation_participating_manage])
    user.account_users.find_by!(account: account).update!(custom_role: role)
    create(:inbox_member, user: user, inbox: conversation.inbox)
    dispatch(:team_changed)
    expect(notifications).to be_empty
    role.update!(permissions: ['conversation_manage'])
    dispatch(:team_changed)
    expect(notifications).to be_empty
  end

  it 'does not notify when an individual agent is assigned' do
    conversation.update!(assignee: user)
    dispatch(:team_changed)
    expect(notifications).to be_empty
  end

  it 'does not notify for an AI assignee' do
    conversation.update!(ai_assignee: create(:agent_bot))
    dispatch(:team_changed)
    expect(notifications).to be_empty
  end

  it 'does not notify for a legacy bot assignee' do
    conversation.update!(assignee_agent_bot_id: create(:agent_bot).id)
    dispatch(:team_changed)
    expect(notifications).to be_empty
  end

  it 'does not notify for pending or resolved conversations' do
    conversation.update!(status: :pending)
    dispatch(:team_changed)
    conversation.update!(status: :resolved)
    dispatch(:team_changed)
    expect(notifications).to be_empty
  end

  it 'does not notify for a blocked contact' do
    conversation.contact.update!(blocked: true)
    dispatch(:team_changed)
    expect(notifications).to be_empty
  end

  it 'notifies when an agent is removed from a conversation still assigned to the team' do
    dispatch(:assignee_changed, 'assignee_id' => [user.id, nil])
    expect(notifications.count).to eq(1)
  end

  it 'lets a simultaneous team change own the transition without duplicate notifications' do
    changes = { 'team_id' => [nil, team.id], 'assignee_id' => [user.id, nil] }
    dispatch(:assignee_changed, changes)
    dispatch(:team_changed, changes)
    expect(notifications.count).to eq(1)
  end

  it 'ignores a delayed team event after the conversation moves to another team' do
    other_team = create(:team, account: account, allow_auto_assign: false)
    conversation.update!(team: other_team)
    dispatch(:team_changed, 'team_id' => [nil, team.id])
    expect(notifications).to be_empty
  end

  it 'does not notify after the team is removed' do
    conversation.update!(team: nil)
    dispatch(:team_changed, 'team_id' => [team.id, nil])
    expect(notifications).to be_empty
  end

  it 'preserves the existing individual assignment notification' do
    conversation.update!(assignee: user)
    event = Events::Base.new('assignee.changed', Time.current, conversation: conversation, notifiable_assignee_change: true)
    listener.assignee_changed(event)
    expect(user.notifications.conversation_assignment.count).to eq(1)
    expect(notifications).to be_empty
  end

  it 'uses the actual team-change dispatch after a conversation save' do
    conversation.update!(team: nil)
    clear_enqueued_jobs
    perform_enqueued_jobs(only: EventDispatcherJob) { conversation.update!(team: team) }
    expect(notifications.count).to eq(1)
  end

  it 'uses the actual assignee-clear dispatch without waiting for a new message' do
    conversation.update!(assignee: user)
    clear_enqueued_jobs
    perform_enqueued_jobs(only: EventDispatcherJob) { conversation.update!(assignee: nil) }
    expect(notifications.count).to eq(1)
  end

  it 'creates only one notice when the same event job is processed twice' do
    conversation.update!(team: nil)
    clear_enqueued_jobs
    conversation.update!(team: team)
    job = enqueued_jobs.find { |entry| entry[:job] == EventDispatcherJob && entry[:args].first == 'team.changed' }
    args = ActiveJob::Arguments.deserialize(job.fetch(:args))
    2.times { EventDispatcherJob.perform_now(*args) }
    expect(notifications.count).to eq(1)
  end

  it 'preserves the team name at assignment even when it is renamed before the job runs' do
    original_name = conversation.team.name
    team.update!(name: 'Renamed before dispatch')
    dispatch(:team_changed)
    expect(notifications.last.push_message_title).to include(original_name)
    expect(notifications.last.meta['assignment_team_name']).to eq(original_name)
  end

  it 'ignores an old event after the team cycles A to B to A, but permits the latest transition' do
    original_attributes = conversation.additional_attributes.deep_dup
    other_team = create(:team, account: account, allow_auto_assign: false)
    conversation.update!(team: other_team)
    conversation.update!(team: team)
    dispatch(:team_changed, 'team_id' => [nil, team.id], 'additional_attributes' => [nil, original_attributes])
    expect(notifications).to be_empty
    dispatch(:team_changed, 'team_id' => [other_team.id, team.id])
    expect(notifications.count).to eq(1)
  end

  it 'does not reinterpret pre-upgrade events without a transition identity as new assignments' do
    event = Events::Base.new('team.changed', Time.current, conversation: conversation, changed_attributes: { 'team_id' => [nil, team.id] })
    listener.team_changed(event)
    expect(notifications).to be_empty
  end

  it 'resumes a partially failed fanout without duplicating already committed recipients' do
    other_user = create(:user, account: account)
    team.members << other_user
    other_user.notification_settings.find_by!(account: account).update!(selected_push_flags: ['push_team_conversation_assignment'])
    failed_once = false
    allow(NotificationBuilder).to receive(:new).and_wrap_original do |method, *args|
      builder = method.call(*args)
      if args.first[:user] == other_user && !failed_once
        failed_once = true
        allow(builder).to receive(:perform).and_raise('partial fanout failure')
      end
      builder
    end
    expect { dispatch(:team_changed) }.to raise_error('partial fanout failure')
    expect(notifications.count).to eq(1)
    dispatch(:team_changed)
    expect(notifications.count).to eq(1)
    expect(other_user.notifications.team_conversation_assignment.count).to eq(1)
  end
end
