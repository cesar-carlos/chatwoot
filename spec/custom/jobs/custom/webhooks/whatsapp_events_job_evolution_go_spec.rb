# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Webhooks::WhatsappEventsJobEvolutionGo do
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
        'instance_token' => 'token'
      )
    )
  end
  let(:inbox) { channel.inbox }

  before { channel }

  it 'dispatches MESSAGE events through the normalizer' do
    payload = JSON.parse(Rails.root.join('spec/fixtures/evolution_go/message_inbound.json').read)
    job_payload = payload.merge(
      'evolution_go_instance_name' => 'test-go-instance',
      'channel_id' => channel.id
    )

    expect(Custom::Whatsapp::Webhooks::EvolutionGoNormalizer).to receive(:new)
      .with(channel, hash_including('event' => 'Message'))
      .and_call_original

    expect do
      Webhooks::WhatsappEventsJob.perform_now(job_payload)
    end.to change(Message, :count).by(1)
  end

  it 'dispatches READ_RECEIPT events as statuses' do
    payload = JSON.parse(Rails.root.join('spec/fixtures/evolution_go/read_receipt.json').read)
    payload['event'] = 'READ_RECEIPT'
    conversation = create(:conversation, account: account, inbox: inbox)
    existing = create(
      :message,
      account: account,
      inbox: inbox,
      conversation: conversation,
      message_type: :outgoing,
      source_id: '3EB0READRECEIPT01',
      status: :delivered
    )

    normalized = Custom::Whatsapp::Webhooks::EvolutionGoReadReceiptNormalizer.new(channel, payload).perform
    expect(normalized).to be_present

    Custom::Whatsapp::EvolutionGo::InboundMessageProcessor.process(
      channel,
      normalized.merge(phone_number: channel.phone_number)
    )

    expect(existing.reload.status).to eq('read')
  end

  it 'routes READ_RECEIPT events through the read receipt normalizer in the job' do
    payload = JSON.parse(Rails.root.join('spec/fixtures/evolution_go/read_receipt.json').read)
    payload['event'] = 'READ_RECEIPT'
    job_payload = payload.merge(
      'evolution_go_instance_name' => 'test-go-instance',
      'channel_id' => channel.id
    )

    expect(Custom::Whatsapp::Webhooks::EvolutionGoReadReceiptNormalizer).to receive(:new)
      .with(channel, hash_including('event' => 'READ_RECEIPT'))
      .and_call_original

    Webhooks::WhatsappEventsJob.perform_now(job_payload)
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
