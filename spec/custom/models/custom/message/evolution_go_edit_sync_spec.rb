# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Custom::Message::EvolutionGoEditSync' do
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
      source_id: 'OUT-EDIT-HOOK-1',
      content: 'original',
      content_attributes: { evolution_go_remote_jid: '5511999999999@s.whatsapp.net' }
    )
  end
  let(:edit_sync) { instance_double(Custom::Whatsapp::EvolutionGo::EditSyncService, perform: true) }

  before do
    message
    allow(Custom::Whatsapp::EvolutionGo::EditSyncService).to receive(:new).and_return(edit_sync)
  end

  it 'dispatches EditSyncService when outgoing content changes without webhook marker' do
    message.update!(content: 'edited by agent')

    expect(Custom::Whatsapp::EvolutionGo::EditSyncService).to have_received(:new).with(message: message)
    expect(edit_sync).to have_received(:perform)
  end

  it 'skips EditSyncService while edited_via_evolution_go_webhook remains set' do
    message.update!(
      content: "Edited message:\n\nfirst phone edit",
      content_attributes: message.content_attributes.merge(
        'edited' => true,
        'edited_via_evolution_go_webhook' => true
      )
    )
    expect(Custom::Whatsapp::EvolutionGo::EditSyncService).not_to have_received(:new)

    message.update!(
      content: "Edited message:\n\nsecond phone edit",
      content_attributes: message.content_attributes.merge(
        'edited' => true,
        'edited_via_evolution_go_webhook' => true
      )
    )
    expect(Custom::Whatsapp::EvolutionGo::EditSyncService).not_to have_received(:new)
  end

  it 'dispatches when webhook marker is cleared before agent edit' do
    message.update!(
      content: "Edited message:\n\nfrom phone",
      content_attributes: message.content_attributes.merge('edited_via_evolution_go_webhook' => true)
    )
    allow(Custom::Whatsapp::EvolutionGo::EditSyncService).to receive(:new).and_return(edit_sync)

    message.update!(
      content: 'agent rewrite',
      content_attributes: message.content_attributes.merge('edited_via_evolution_go_webhook' => false)
    )

    expect(Custom::Whatsapp::EvolutionGo::EditSyncService).to have_received(:new).with(message: message)
  end
end
