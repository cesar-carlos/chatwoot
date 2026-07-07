# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Whatsapp::Webhooks::EvolutionGoReadReceiptNormalizer do
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
  let(:fixture) do
    JSON.parse(Rails.root.join('spec/fixtures/evolution_go/read_receipt.json').read)
  end

  it 'normalizes Receipt events to flat statuses' do
    result = described_class.new(channel, fixture).perform

    expect(result[:statuses].first[:id]).to eq('3EB0READRECEIPT01')
    expect(result[:statuses].first[:status]).to eq('read')
    expect(result[:statuses].first[:recipient_id]).to eq('5511999999999')
  end

  it 'maps Delivered receipts separately from Read' do
    payload = fixture.deep_dup
    payload['state'] = 'Delivered'
    payload['data']['Type'] = 'delivered'

    result = described_class.new(channel, payload).perform

    expect(result[:statuses].first[:status]).to eq('delivered')
  end
end
