require 'rails_helper'

RSpec.describe ActionCableListener do
  let(:listener) { described_class.instance }
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }
  let(:allowed_agent) { create(:user, account: account, role: :agent) }
  let(:restricted_agent) { create(:user, account: account, role: :agent) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: allowed_agent) }
  let(:message) { create(:message, message_type: :outgoing, account: account, inbox: inbox, conversation: conversation) }
  let(:event) { Events::Base.new(:'message.created', Time.zone.now, message: message) }

  before do
    create(:inbox_member, inbox: inbox, user: allowed_agent)
    create(:inbox_member, inbox: inbox, user: restricted_agent)
    account.account_users.find_by!(user: restricted_agent).update!(
      custom_role: create(:custom_role, account: account, permissions: ['conversation_participating_manage'])
    )
    Current.user = nil
    Current.account = nil
  end

  it 'does not broadcast conversation data to an inbox member denied by the custom role' do
    expect(ActionCableBroadcastJob).to receive(:perform_later).with(
      a_collection_containing_exactly(
        allowed_agent.pubsub_token,
        admin.pubsub_token,
        conversation.contact_inbox.pubsub_token
      ),
      'message.created',
      message.push_event_data.merge(account_id: account.id)
    )

    listener.message_created(event)
  end

  it 'removes account user tokens when a conversation event cannot be resolved' do
    payload = { conversation_id: nil }

    expect(ActionCableBroadcastJob).to receive(:perform_later).with(
      [conversation.contact_inbox.pubsub_token],
      'message.created',
      payload.merge(account_id: account.id)
    )

    listener.send(
      :broadcast,
      account,
      [allowed_agent.pubsub_token, conversation.contact_inbox.pubsub_token],
      'message.created',
      payload
    )
  end
end
