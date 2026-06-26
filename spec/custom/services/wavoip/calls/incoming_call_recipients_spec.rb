# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Wavoip::Calls::IncomingCallRecipients do
  subject(:recipients) { described_class.new(inbox: inbox, conversation: conversation) }

  let(:account) { create(:account) }
  let(:channel) { create(:channel_wavoip, account: account) }
  let(:inbox) { channel.inbox }
  let!(:online_agent) { create(:user, account: account, role: :agent) }
  let!(:offline_member) { create(:user, account: account, role: :agent) }
  let!(:admin) { create(:user, :administrator, account: account) }
  let(:conversation) do
    create(:conversation, account: account, inbox: inbox, assignee: offline_member)
  end

  before do
    account.enable_features!('channel_voice', 'channel_wavoip')
    create(:inbox_member, inbox: inbox, user: online_agent)
    create(:inbox_member, inbox: inbox, user: offline_member)
    online_agent.account_users.find_by(account: account).update!(availability: :online)
    offline_member.account_users.find_by(account: account).update!(availability: :offline)
    allow(OnlineStatusTracker).to receive(:get_users_with_status)
      .with(account.id, user_ids: kind_of(Array), status: 'online')
      .and_return({ online_agent.id.to_s => 'online' })
    allow(OnlineStatusTracker).to receive(:get_users_with_status)
      .with(account.id, user_ids: kind_of(Array), status: 'busy')
      .and_return({})
  end

  it 'returns online inbox members when any are online' do
    expect(recipients.users.pluck(:id)).to eq([online_agent.id])
  end

  context 'when include_administrators is enabled and an administrator is online' do
    before do
      allow(OnlineStatusTracker).to receive(:get_users_with_status)
        .with(account.id, user_ids: kind_of(Array), status: 'online')
        .and_return({ admin.id.to_s => 'online' })
    end

    it 'includes the online administrator in the initial ring' do
      expect(recipients.users.pluck(:id)).to include(admin.id)
    end

    it 'does not include offline inbox members' do
      expect(recipients.users.pluck(:id)).not_to include(online_agent.id, offline_member.id)
    end
  end

  context 'when include_administrators is disabled and only the administrator is online' do
    before do
      channel.update!(
        provider_config: channel.provider_config.merge('incoming_call_include_administrators' => false)
      )
      allow(OnlineStatusTracker).to receive(:get_users_with_status)
        .with(account.id, user_ids: kind_of(Array), status: 'online')
        .and_return({ admin.id.to_s => 'online' })
    end

    it 'does not include the administrator in the initial ring' do
      expect(recipients.users.pluck(:id)).not_to include(admin.id)
    end
  end

  context 'when no agents are online' do
    before do
      allow(OnlineStatusTracker).to receive(:get_users_with_status)
        .with(account.id, user_ids: kind_of(Array), status: 'online')
        .and_return({})
    end

    it 'defaults to assignee then inbox members and administrators' do
      expect(recipients.users.pluck(:id)).to eq([offline_member.id])
    end

    it 'falls back to inbox members and administrators when assignee is absent' do
      conversation.update!(assignee: nil)

      expect(recipients.users.pluck(:id)).to contain_exactly(
        online_agent.id,
        offline_member.id,
        admin.id
      )
    end

    it 'excludes administrators when incoming_call_include_administrators is false' do
      conversation.update!(assignee: nil)
      channel.update!(
        provider_config: channel.provider_config.merge('incoming_call_include_administrators' => false)
      )

      expect(recipients.users.pluck(:id)).to contain_exactly(online_agent.id, offline_member.id)
    end

    it 'does not notify anyone when offline fallback is none' do
      channel.update!(
        provider_config: channel.provider_config.merge('incoming_call_offline_fallback' => 'none')
      )

      expect(recipients.users).to be_empty
    end

    it 'notifies only assignee when offline fallback is assignee' do
      channel.update!(
        provider_config: channel.provider_config.merge('incoming_call_offline_fallback' => 'assignee')
      )

      expect(recipients.users.pluck(:id)).to eq([offline_member.id])
    end

    it 'does not notify anyone when offline fallback is assignee and assignee is absent' do
      conversation.update!(assignee: nil)
      channel.update!(
        provider_config: channel.provider_config.merge('incoming_call_offline_fallback' => 'assignee')
      )

      expect(recipients.users).to be_empty
    end

    it 'notifies inbox members when offline fallback is assignee_or_inbox_members and assignee is absent' do
      conversation.update!(assignee: nil)
      channel.update!(
        provider_config: channel.provider_config.merge('incoming_call_offline_fallback' => 'assignee_or_inbox_members')
      )

      expect(recipients.users.pluck(:id)).to contain_exactly(online_agent.id, offline_member.id)
    end

    it 'notifies team members when offline fallback is assignee_or_team_members and assignee is absent' do
      team_agent = create(:user, account: account, role: :agent)
      team = create(:team, account: account)
      create(:team_member, team: team, user: team_agent)
      conversation.update!(assignee: nil, team: team)
      channel.update!(
        provider_config: channel.provider_config.merge('incoming_call_offline_fallback' => 'assignee_or_team_members')
      )

      expect(recipients.users.pluck(:id)).to eq([team_agent.id])
    end
  end

  context 'when notify_busy_agents is enabled' do
    let!(:busy_agent) { create(:user, account: account, role: :agent) }

    before do
      create(:inbox_member, inbox: inbox, user: busy_agent)
      channel.update!(
        provider_config: channel.provider_config.merge('incoming_call_notify_busy_agents' => true)
      )
      allow(OnlineStatusTracker).to receive(:get_users_with_status)
        .with(account.id, user_ids: kind_of(Array), status: 'online')
        .and_return({})
      allow(OnlineStatusTracker).to receive(:get_users_with_status)
        .with(account.id, user_ids: kind_of(Array), status: 'busy')
        .and_return(
          { busy_agent.id.to_s => 'busy' }
        )
    end

    it 'returns busy inbox members before offline fallback' do
      expect(recipients.users.pluck(:id)).to eq([busy_agent.id])
    end

    it 'ignores busy agents who are not inbox members or administrators' do
      non_member_busy = create(:user, account: account, role: :agent)
      allow(OnlineStatusTracker).to receive(:get_users_with_status)
        .with(account.id, user_ids: kind_of(Array), status: 'online')
        .and_return({})
      allow(OnlineStatusTracker).to receive(:get_users_with_status)
        .with(account.id, user_ids: kind_of(Array), status: 'busy')
        .and_return(
          {
            busy_agent.id.to_s => 'busy',
            non_member_busy.id.to_s => 'busy'
          }
        )

      expect(recipients.users.pluck(:id)).to eq([busy_agent.id])
    end

    context 'when include_administrators is enabled and an administrator is busy' do
      before do
        allow(OnlineStatusTracker).to receive(:get_users_with_status)
          .with(account.id, user_ids: kind_of(Array), status: 'online')
          .and_return({})
        allow(OnlineStatusTracker).to receive(:get_users_with_status)
          .with(account.id, user_ids: kind_of(Array), status: 'busy')
          .and_return({ admin.id.to_s => 'busy' })
      end

      it 'includes the busy administrator before falling back to offline recipients' do
        expect(recipients.users.pluck(:id)).to include(admin.id)
      end
    end

    context 'when include_administrators is disabled and only the administrator is busy' do
      before do
        channel.update!(
          provider_config: channel.provider_config.merge(
            'incoming_call_notify_busy_agents' => true,
            'incoming_call_include_administrators' => false
          )
        )
        allow(OnlineStatusTracker).to receive(:get_users_with_status)
          .with(account.id, user_ids: kind_of(Array), status: 'online')
          .and_return({})
        allow(OnlineStatusTracker).to receive(:get_users_with_status)
          .with(account.id, user_ids: kind_of(Array), status: 'busy')
          .and_return({ admin.id.to_s => 'busy' })
      end

      it 'does not include the busy administrator' do
        expect(recipients.users.pluck(:id)).not_to include(admin.id)
      end
    end
  end

  describe '#escalated_users' do
    it 'returns inbox members and administrators' do
      expect(recipients.escalated_users.pluck(:id)).to contain_exactly(
        online_agent.id,
        offline_member.id,
        admin.id
      )
    end

    it 'returns no users when offline fallback is none' do
      channel.update!(
        provider_config: channel.provider_config.merge('incoming_call_offline_fallback' => 'none')
      )

      expect(recipients.escalated_users).to be_empty
    end

    context 'when notify_busy_agents is enabled' do
      let!(:busy_agent) { create(:user, account: account, role: :agent) }

      before do
        create(:inbox_member, inbox: inbox, user: busy_agent)
        channel.update!(
          provider_config: channel.provider_config.merge('incoming_call_notify_busy_agents' => true)
        )
        allow(OnlineStatusTracker).to receive(:get_users_with_status)
          .with(account.id, user_ids: kind_of(Array), status: 'online')
          .and_return({})
        allow(OnlineStatusTracker).to receive(:get_users_with_status)
          .with(account.id, user_ids: kind_of(Array), status: 'busy')
          .and_return({ busy_agent.id.to_s => 'busy' })
      end

      it 'returns busy inbox members before broad fallback' do
        expect(recipients.escalated_users.pluck(:id)).to eq([busy_agent.id])
      end
    end
  end
end
