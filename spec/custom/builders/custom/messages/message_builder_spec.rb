# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Messages::MessageBuilder do
  describe 'Wavoip voice-only inbox' do
    let(:account) { create(:account) }
    let(:channel) { create(:channel_wavoip, account: account) }
    let(:inbox) { channel.inbox }
    let(:conversation) { create(:conversation, account: account, inbox: inbox) }
    let(:agent) { create(:user, account: account) }

    before do
      account.enable_features!('channel_voice', 'channel_wavoip')
    end

    it 'rejects outgoing public text messages' do
      expect do
        described_class.new(agent, conversation, { content: 'Hello', message_type: 'outgoing' }).perform
      end.to raise_error(CustomExceptions::Wavoip::VoiceOnlyInbox)
    end

    it 'rejects outgoing public attachment-only messages' do
      expect do
        described_class.new(
          agent,
          conversation,
          { content: '', message_type: 'outgoing', attachments: ['signed-blob-id'] }
        ).perform
      end.to raise_error(CustomExceptions::Wavoip::VoiceOnlyInbox)
    end

    it 'allows private notes' do
      message = described_class.new(
        agent,
        conversation,
        { content: 'Internal note', message_type: 'outgoing', private: true }
      ).perform

      expect(message).to be_persisted
      expect(message.private).to be true
    end

    it 'allows voice_call system messages' do
      message = described_class.new(
        nil,
        conversation,
        {
          content: I18n.t('conversations.messages.voice_call.wavoip'),
          message_type: 'outgoing',
          content_type: 'voice_call',
          content_attributes: { 'data' => { 'status' => 'ringing' } }
        }
      ).perform

      expect(message).to be_persisted
      expect(message.content_type).to eq('voice_call')
    end
  end

  describe 'conversation_reply_assigned_only' do
    let(:account) { create(:account) }
    let(:inbox) { create(:inbox, account: account) }
    let(:agent) { create(:user, account: account, role: :agent) }
    let(:agent_account_user) { agent.account_users.find_by(account: account) }

    before do
      create(:inbox_member, user: agent, inbox: inbox)
    end

    context 'when custom role includes the restriction' do
      let(:custom_role) do
        create(
          :custom_role,
          account: account,
          permissions: %w[conversation_unassigned_manage conversation_reply_assigned_only]
        )
      end

      before do
        agent_account_user.update!(custom_role: custom_role)
      end

      it 'raises NotAuthorizedError for unassigned conversations' do
        conversation = create(:conversation, account: account, inbox: inbox, assignee: nil)

        expect do
          described_class.new(agent, conversation, { content: 'Hello', message_type: 'outgoing' }).perform
        end.to raise_error(Pundit::NotAuthorizedError)
      end

      it 'allows messages when assigned to the agent' do
        conversation = create(:conversation, account: account, inbox: inbox, assignee: agent)

        message = described_class.new(
          agent,
          conversation,
          { content: 'Hello', message_type: 'outgoing' }
        ).perform

        expect(message).to be_persisted
      end

      it 'allows system/automation messages without a user' do
        conversation = create(:conversation, account: account, inbox: inbox, assignee: nil)

        message = described_class.new(
          nil,
          conversation,
          { content: 'Auto', message_type: 'outgoing' }
        ).perform

        expect(message).to be_persisted
      end
    end

    context 'when custom role does not include the restriction' do
      let(:custom_role) do
        create(:custom_role, account: account, permissions: ['conversation_unassigned_manage'])
      end

      before do
        agent_account_user.update!(custom_role: custom_role)
      end

      it 'allows messages on unassigned conversations' do
        conversation = create(:conversation, account: account, inbox: inbox, assignee: nil)

        message = described_class.new(
          agent,
          conversation,
          { content: 'Hello', message_type: 'outgoing' }
        ).perform

        expect(message).to be_persisted
      end
    end
  end
end
