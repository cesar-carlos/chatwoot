# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Captain::Copilot::ChatService do
  let(:account) { create(:account, custom_attributes: { plan_name: 'startups' }) }
  let(:user) { create(:user, account: account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:copilot_thread) { create(:captain_copilot_thread, account: account, user: user) }
  let(:config) do
    { user_id: user.id, copilot_thread_id: copilot_thread.id, conversation_id: conversation.display_id }
  end

  let(:mock_chat) { instance_double(RubyLLM::Chat) }
  let(:mock_context) { instance_double(RubyLLM::Context) }
  let(:mock_response) do
    instance_double(RubyLLM::Message, content: '{ "content": "Hey", "reasoning": "ok", "reply_suggestion": false }')
  end

  before do
    allow(Integrations::Openai::KeyValidator).to receive(:valid?).and_return(true)

    allow(RubyLLM).to receive(:context) do |&block|
      config_double = instance_double('config').as_null_object # rubocop:disable RSpec/VerifiedDoubleReference
      block&.call(config_double)
      mock_context
    end
    allow(mock_context).to receive(:chat).and_return(mock_chat)
    allow(mock_chat).to receive(:with_temperature).and_return(mock_chat)
    allow(mock_chat).to receive(:with_params).and_return(mock_chat)
    allow(mock_chat).to receive(:with_tool).and_return(mock_chat)
    allow(mock_chat).to receive(:with_instructions).and_return(mock_chat)
    allow(mock_chat).to receive(:add_message).and_return(mock_chat)
    allow(mock_chat).to receive(:on_end_message).and_return(mock_chat)
    allow(mock_chat).to receive(:on_tool_call).and_return(mock_chat)
    allow(mock_chat).to receive(:on_tool_result).and_return(mock_chat)
    allow(mock_chat).to receive(:messages).and_return([])
    allow(mock_chat).to receive(:ask).and_return(mock_response)
  end

  describe 'BYOK credential usage' do
    it 'uses the account OpenAI hook key and does not increment usage' do
      create(:integrations_hook, :openai, account: account, settings: { 'api_key' => 'hook-key' })
      create(:installation_config, name: 'CAPTAIN_OPEN_AI_API_KEY', value: 'system-key')

      service = described_class.new(assistant, config)
      expect do
        service.generate_response('Hello')
      end.not_to(change { account.reload.custom_attributes['captain_responses_usage'].to_i })

      expect(service.llm_credential).to eq(api_key: 'hook-key', source: :hook)
    end

    it 'falls back to the system key and increments usage' do
      create(:installation_config, name: 'CAPTAIN_OPEN_AI_API_KEY', value: 'system-key')

      service = described_class.new(assistant, config)
      expect do
        service.generate_response('Hello')
      end.to(change { account.reload.custom_attributes['captain_responses_usage'].to_i }.by(1))

      expect(service.llm_credential).to eq(api_key: 'system-key', source: :system)
    end

    it 'raises a clear error when no API key is configured' do
      expect do
        described_class.new(assistant, config).generate_response('Hello')
      end.to raise_error(StandardError, I18n.t('captain.api_key_missing'))
    end
  end
end
