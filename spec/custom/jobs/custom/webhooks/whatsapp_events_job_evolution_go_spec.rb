# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Webhooks::WhatsappEventsJobEvolutionGo do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account, channel: channel) }
  let(:channel) do
    create(
      :channel_whatsapp,
      account: account,
      provider: 'evolution_go',
      sync_templates: false,
      validate_provider_config: false,
      provider_config: Custom::Whatsapp::EvolutionGo::ProviderConfig.build(
        'instance_name' => 'test-go-instance',
        'instance_token' => 'token'
      )
    )
  end

  before { inbox }

  it 'dispatches MESSAGE events through the normalizer' do
    payload = JSON.parse(Rails.root.join('spec/fixtures/evolution_go/message_inbound.json').read)
    job_payload = payload.merge(
      'evolution_go_instance_name' => 'test-go-instance',
      'channel_id' => channel.id
    )

    expect(Custom::Whatsapp::Webhooks::EvolutionGoNormalizer).to receive(:new)
      .with(channel, hash_including('event' => 'MESSAGE'))
      .and_call_original

    expect do
      Webhooks::WhatsappEventsJob.perform_now(job_payload)
    end.to change(Message, :count).by(1)
  end

  it 'dispatches READ_RECEIPT events as statuses' do
    payload = JSON.parse(Rails.root.join('spec/fixtures/evolution_go/read_receipt.json').read)
    job_payload = payload.merge(
      'evolution_go_instance_name' => 'test-go-instance',
      'channel_id' => channel.id
    )
    existing = create(
      :message,
      account: account,
      inbox: inbox,
      source_id: '3EB0READRECEIPT01',
      status: :delivered
    )

    Webhooks::WhatsappEventsJob.perform_now(job_payload)

    expect(existing.reload.status).to eq('read')
  end

  it 'delegates unknown evolution_go channels to super without dropping' do
    payload = {
      'event' => 'MESSAGE',
      'evolution_go_instance_name' => 'missing',
      'channel_id' => 0,
      'phone_number' => channel.phone_number,
      'contacts' => [{ 'wa_id' => '5511999999999', 'profile' => { 'name' => 'Test' } }],
      'messages' => [{
        'from' => '5511999999999',
        'id' => 'msg-1',
        'timestamp' => '1',
        'type' => 'text',
        'text' => { 'body' => 'hello' }
      }]
    }

    expect do
      Webhooks::WhatsappEventsJob.perform_now(payload)
    end.to change(Message, :count).by(1)
  end
end
