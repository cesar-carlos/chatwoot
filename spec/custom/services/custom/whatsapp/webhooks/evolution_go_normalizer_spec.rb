# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Whatsapp::Webhooks::EvolutionGoNormalizer do
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
    JSON.parse(Rails.root.join('spec/fixtures/evolution_go/message_inbound.json').read)
  end

  it 'normalizes inbound text MESSAGE events' do
    result = described_class.new(channel, fixture).perform

    expect(result[:contacts].first[:wa_id]).to eq('5511999999999')
    expect(result[:messages].first[:id]).to eq('3EB0C5A277F7F9B6C599')
    expect(result[:messages].first[:text][:body]).to eq('Olá from Evolution Go!')
  end

  it 'filters fromMe echo messages' do
    payload = fixture.deep_dup
    payload['data']['key']['fromMe'] = true

    expect(described_class.new(channel, payload).perform).to be_nil
  end

  it 'allows fromMe when ignore_from_me_echo is false' do
    channel.update!(
      provider_config: channel.provider_config.merge('ignore_from_me_echo' => false)
    )
    payload = fixture.deep_dup
    payload['data']['key']['fromMe'] = true

    expect(described_class.new(channel, payload).perform).to be_present
  end

  it 'filters group messages when ignore_groups is true' do
    payload = fixture.deep_dup
    payload['data']['key']['remoteJid'] = '120363012345678901@g.us'

    expect(described_class.new(channel, payload).perform).to be_nil
  end

  it 'normalizes inbound image MESSAGE events' do
    image_fixture = JSON.parse(
      Rails.root.join('spec/fixtures/evolution_go/message_inbound_image.json').read
    )
    result = described_class.new(channel, image_fixture).perform

    expect(result[:messages].first[:type]).to eq('image')
    expect(result[:messages].first[:image][:_evolution_go_message]).to be_present
    expect(result[:messages].first[:image][:caption]).to eq('Photo caption')
  end
end
