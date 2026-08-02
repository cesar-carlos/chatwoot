# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Whatsapp::EvolutionGo::MessageContentEditService do
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
        'sync_edit_to_whatsapp' => true
      )
    )
  end
  let(:inbox) { channel.inbox }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:message) do
    create(
      :message,
      account: account,
      inbox: inbox,
      conversation: conversation,
      message_type: :outgoing,
      source_id: 'OUT-EDIT-UI-1',
      content: 'original text',
      content_attributes: {
        evolution_go_remote_jid: '5511999999999@s.whatsapp.net',
        edited_via_evolution_go_webhook: true
      }
    )
  end
  let(:edit_sync) { instance_double(Custom::Whatsapp::EvolutionGo::EditSyncService, perform: true) }

  before do
    allow(Custom::Whatsapp::EvolutionGo::EditSyncService).to receive(:new).and_return(edit_sync)
  end

  it 'syncs to WhatsApp first, then updates local content without legacy prefix' do
    described_class.new(message: message, content: 'updated from dashboard').perform

    expect(Custom::Whatsapp::EvolutionGo::EditSyncService).to have_received(:new).with(
      message: message,
      content: 'updated from dashboard',
      raise_errors: true
    )
    expect(edit_sync).to have_received(:perform)

    message.reload
    expect(message.content).to eq('updated from dashboard')
    expect(message.content_attributes['edited']).to be(true)
    expect(message.content_attributes['edited_via_evolution_go_webhook']).to be(false)
  end

  it 'does not change the record when WhatsApp sync fails' do
    allow(edit_sync).to receive(:perform).and_raise(
      Custom::Whatsapp::EvolutionGo::ApiError, 'Failed to edit message on WhatsApp'
    )

    expect do
      described_class.new(message: message, content: 'updated from dashboard').perform
    end.to raise_error(Custom::Whatsapp::EvolutionGo::ApiError, /Failed to edit/)

    expect(message.reload.content).to eq('original text')
  end

  it 'does not change the record when content is unchanged' do
    expect do
      described_class.new(message: message, content: 'original text').perform
    end.not_to(change { message.reload.updated_at })

    expect(Custom::Whatsapp::EvolutionGo::EditSyncService).not_to have_received(:new)
  end

  it 'raises when sync_edit_to_whatsapp is disabled' do
    channel.update!(
      provider_config: channel.provider_config.merge('sync_edit_to_whatsapp' => false)
    )

    expect do
      described_class.new(message: message, content: 'nope').perform
    end.to raise_error(Custom::Whatsapp::EvolutionGo::ApiError, /disabled/)
  end

  it 'raises for incoming messages' do
    incoming = create(
      :message,
      account: account,
      inbox: inbox,
      conversation: conversation,
      message_type: :incoming,
      source_id: 'IN-1',
      content: 'hello'
    )

    expect do
      described_class.new(message: incoming, content: 'edited').perform
    end.to raise_error(Custom::Whatsapp::EvolutionGo::ApiError, /outgoing/)
  end

  it 'strips legacy edited prefix when comparing noop / editing' do
    # Seed legacy content without callbacks that would re-normalize the prefix.
    message.update_columns(content: "#{described_class::EDITED_PREFIX}legacy body") # rubocop:disable Rails/SkipsModelValidations

    described_class.new(message: message, content: 'legacy body').perform
    expect(Custom::Whatsapp::EvolutionGo::EditSyncService).not_to have_received(:new)

    described_class.new(message: message, content: 'new body').perform
    expect(edit_sync).to have_received(:perform)
    expect(message.reload.content).to eq('new body')
  end
end
