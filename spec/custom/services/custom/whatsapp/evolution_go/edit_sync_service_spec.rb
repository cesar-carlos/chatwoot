# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Whatsapp::EvolutionGo::EditSyncService do
  let(:account) { create(:account) }
  let(:channel) do
    create(
      :channel_whatsapp,
      account: account,
      provider: 'evolution_go',
      sync_templates: false,
      validate_provider_config: false,
      provider_config: Custom::Whatsapp::EvolutionGo::ProviderConfig.build(
        'instance_name' => 'test-go-instance',
        'instance_token' => 'TEST-TOKEN',
        'base_url' => 'https://evogo.example.com',
        'sync_edit_to_whatsapp' => true,
        'convert_markdown_outbound' => true,
        'sign_msg' => false
      )
    )
  end
  let(:inbox) { channel.inbox }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:agent) { create(:user, account: account, name: 'Agent Name') }
  let(:message) do
    create(
      :message,
      account: account,
      inbox: inbox,
      conversation: conversation,
      message_type: :outgoing,
      sender: agent,
      source_id: 'OUT-EDIT-1',
      content: '**bold** text',
      content_attributes: { evolution_go_remote_jid: '5511999999999@s.whatsapp.net' }
    )
  end
  let(:api_client) { instance_double(Custom::Whatsapp::EvolutionGo::ApiClient) }
  let(:response) { instance_double(HTTParty::Response, success?: true, code: 200) }

  before do
    allow(Custom::Whatsapp::EvolutionGo::ApiClient).to receive(:for_channel).with(channel).and_return(api_client)
  end

  it 'calls Evolution Go edit API with markdown converted body' do
    expect(api_client).to receive(:edit_message) do |args|
      expect(args[:chat]).to eq('5511999999999@s.whatsapp.net')
      expect(args[:message_id]).to eq('OUT-EDIT-1')
      expect(args[:message]).to include('*bold*')
      response
    end

    expect(described_class.new(message: message).perform).to be(true)
  end

  it 'uses explicit content override when provided' do
    expect(api_client).to receive(:edit_message).with(
      hash_including(message: a_string_including('*new*'))
    ).and_return(response)

    described_class.new(message: message, content: '**new** text').perform
  end

  it 'raises when raise_errors is true and API fails' do
    failed = instance_double(HTTParty::Response, success?: false, code: 400, parsed_response: { 'error' => 'too late' })
    allow(api_client).to receive(:edit_message).and_return(failed)

    expect do
      described_class.new(message: message, raise_errors: true).perform
    end.to raise_error(Custom::Whatsapp::EvolutionGo::ApiError)
  end

  it 'soft-fails when raise_errors is false and API fails' do
    failed = instance_double(HTTParty::Response, success?: false, code: 400, parsed_response: {})
    allow(api_client).to receive(:edit_message).and_return(failed)

    expect(described_class.new(message: message).perform).to be(false)
  end

  it 'skips when sync_edit_to_whatsapp is disabled' do
    channel.update!(
      provider_config: channel.provider_config.merge('sync_edit_to_whatsapp' => false)
    )

    expect(api_client).not_to receive(:edit_message)

    expect(described_class.new(message: message).perform).to be(false)
  end

  it 'skips incoming messages' do
    incoming = create(
      :message,
      account: account,
      inbox: inbox,
      conversation: conversation,
      message_type: :incoming,
      source_id: 'IN-EDIT-1',
      content: 'hello'
    )

    expect(api_client).not_to receive(:edit_message)

    described_class.new(message: incoming).perform
  end
end
