# frozen_string_literal: true

require 'rails_helper'

# rubocop:disable RSpec/DescribeClass -- integration coverage across opened_by entry points
RSpec.describe 'opened_by improvements' do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }

  describe 'Conversation create' do
    it 'copies Current.conversation_opened_by when the create path does not merge params' do
      Current.conversation_opened_by = 'contact'
      conversation = Conversation.create!(
        account: account,
        inbox: inbox,
        contact: contact,
        contact_inbox: contact_inbox,
        additional_attributes: { 'source' => 'email' }
      )

      expect(conversation.additional_attributes['opened_by']).to eq('contact')
      expect(conversation.additional_attributes['source']).to eq('email')
    ensure
      Current.reset
    end
  end

  describe Custom::Conversations::OpenedByStamper do
    it 'reopens resolved and snoozed episodes as phone and leaves pending alone' do
      resolved = create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox, status: :resolved)
      described_class.reopen_as_phone!(resolved)
      expect(resolved.reload).to be_open
      expect(resolved.additional_attributes['opened_by']).to eq('phone')

      pending = create(:conversation, account: account, inbox: inbox, status: :pending, additional_attributes: { 'opened_by' => 'agent' })
      described_class.reopen_as_phone!(pending)
      expect(pending.reload).to be_pending
      expect(pending.additional_attributes['opened_by']).to eq('agent')
    end
  end

  describe Custom::Conversations::OpenedByBackfill do
    it 'infers contact, phone and agent from the first real message' do
      incoming = create(:conversation, account: account, inbox: inbox)
      create(:message, account: account, inbox: inbox, conversation: incoming, message_type: :activity, content: 'activity')
      create(:message, account: account, inbox: inbox, conversation: incoming, message_type: :incoming, content: 'oi')

      phone = create(:conversation, account: account, inbox: inbox)
      create(:message, account: account, inbox: inbox, conversation: phone, message_type: :outgoing,
                       content_attributes: { 'phone_sent' => true })

      agent = create(:conversation, account: account, inbox: inbox)
      create(:message, account: account, inbox: inbox, conversation: agent, message_type: :outgoing, content: 'hello')

      expect(described_class.perform!(account_id: account.id)).to eq(3)
      expect(incoming.reload.additional_attributes['opened_by']).to eq('contact')
      expect(phone.reload.additional_attributes['opened_by']).to eq('phone')
      expect(agent.reload.additional_attributes['opened_by']).to eq('agent')
    end
  end

  describe Custom::Conversations::OpenedBySummary do
    it 'counts open and pending episodes and keeps blank stamps' do
      create(:conversation, account: account, inbox: inbox, status: :open, additional_attributes: { 'opened_by' => 'contact' })
      create(:conversation, account: account, inbox: inbox, status: :pending, additional_attributes: { 'opened_by' => 'phone' })
      create(:conversation, account: account, inbox: inbox, status: :open, additional_attributes: {})
      create(:conversation, account: account, inbox: inbox, status: :resolved, additional_attributes: { 'opened_by' => 'agent' })

      counts = described_class.counts(account.conversations.where(status: [:open, :pending]))

      expect(counts).to eq(contact: 1, agent: 0, phone: 1, unset: 1)
    end
  end

  describe Sms::IncomingMessageService do
    it 'stamps opened_by=contact on a new conversation' do
      channel = create(:channel_sms, account: account)
      described_class.new(
        inbox: channel.inbox,
        params: {
          id: 'sms-opened-by-1',
          from: '+14234234234',
          to: [channel.phone_number],
          text: 'hello'
        }.with_indifferent_access
      ).perform

      conversation = channel.inbox.conversations.last
      expect(conversation.additional_attributes['opened_by']).to eq('contact')
    end
  end

  describe Messages::Instagram::BaseMessageBuilder do
    it 'uses phone for echoes and contact for inbound' do
      echo = described_class.allocate
      echo.instance_variable_set(:@outgoing_echo, true)
      inbound = described_class.allocate
      inbound.instance_variable_set(:@outgoing_echo, false)

      expect(echo.opened_by_origin).to eq('phone')
      expect(inbound.opened_by_origin).to eq('contact')
    end
  end

  describe Twitter::DirectMessageParserService do
    it 'loads the inbox before classifying the connected account as agent' do
      service = described_class.allocate
      channel = instance_double(Channel::TwitterProfile, profile_id: '42')
      inbox = instance_double(Inbox, channel: channel)
      allow(service).to receive(:set_inbox) { service.instance_variable_set(:@inbox, inbox) }
      allow(service).to receive_messages(source_app_id: 'app', parent_app_id: 'app', message_create_data: { 'sender_id' => '42' })

      expect(Custom::Conversations::OpenedByStamper).to receive(:with_current).with('agent').and_yield

      service.perform
    end
  end

  describe Conversations::FilterService do
    it 'filters by opened_by' do
      user = create(:user, account: account)
      create(:inbox_member, user: user, inbox: inbox)
      match = create(:conversation, account: account, inbox: inbox, additional_attributes: { 'opened_by' => 'contact' })
      create(:conversation, account: account, inbox: inbox, additional_attributes: { 'opened_by' => 'agent' })

      result = described_class.new(
        {
          payload: [
            {
              attribute_key: 'opened_by',
              filter_operator: 'equal_to',
              values: ['contact'],
              query_operator: nil
            }.with_indifferent_access
          ]
        },
        user,
        account
      ).perform

      expect(result[:conversations].map(&:id)).to eq([match.id])
    end
  end
end
# rubocop:enable RSpec/DescribeClass
