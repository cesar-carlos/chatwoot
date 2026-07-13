# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Whatsapp::EvolutionGo::ContactEnrichmentService do
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
  let(:contact) { create(:contact, account: account, phone_number: '+5511999999999', name: '5511999999999') }
  let(:api_client) { instance_double(Custom::Whatsapp::EvolutionGo::ApiClient) }

  before do
    allow(Custom::Whatsapp::EvolutionGo::ApiClient).to receive(:for_channel).and_return(api_client)
  end

  def stub_user_check(exists: true)
    allow(api_client).to receive(:user_check).and_return(
      instance_double(
        HTTParty::Response,
        success?: true,
        parsed_response: {
          'data' => {
            'Users' => [
              {
                'Query' => '+5511999999999@s.whatsapp.net',
                'IsInWhatsapp' => exists,
                'JID' => '5511999999999@s.whatsapp.net'
              }
            ]
          },
          'message' => 'success'
        }
      )
    )
  end

  it 'parses IsInWhatsapp from user/check and attaches avatar from base64' do
    stub_user_check(exists: true)
    allow(api_client).to receive(:user_info).and_return(
      instance_double(HTTParty::Response, success?: true, parsed_response: { 'data' => { 'Users' => {} } })
    )

    png = Base64.strict_encode64(
      "\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x02\x00\x00\x00\x90wS\xDE" \
      "\x00\x00\x00\x0cIDATx\x9Cc\xF8\x0F\x00\x00\x01\x01\x00\x05\x18\xD8N\x00\x00\x00\x00IEND\xAEB`\x82"
    )
    allow(api_client).to receive(:user_avatar).with(number: '5511999999999', preview: true).and_return(
      instance_double(
        HTTParty::Response,
        success?: true,
        parsed_response: { 'success' => true, 'avatar' => png }
      )
    )

    described_class.new(channel: channel, contact: contact, force: true).perform

    expect(contact.reload.avatar).to be_attached
    expect(contact.additional_attributes['evolution_go_enriched_at']).to be_present
  end

  it 'does not fetch avatar when IsInWhatsapp is false' do
    stub_user_check(exists: false)
    expect(api_client).not_to receive(:user_avatar)

    described_class.new(channel: channel, contact: contact, force: true).perform

    expect(contact.reload.avatar).not_to be_attached
  end

  it 'enqueues AvatarFromUrlJob when avatar response contains an HTTP URL' do
    stub_user_check(exists: true)
    allow(api_client).to receive(:user_info).and_return(
      instance_double(HTTParty::Response, success?: true, parsed_response: { 'data' => { 'Users' => {} } })
    )
    allow(api_client).to receive(:user_avatar).and_return(
      instance_double(
        HTTParty::Response,
        success?: true,
        parsed_response: { 'data' => { 'url' => 'https://cdn.example.com/avatar.jpg' } }
      )
    )
    expect(Avatar::AvatarFromUrlJob).to receive(:perform_later).with(contact, 'https://cdn.example.com/avatar.jpg')

    described_class.new(channel: channel, contact: contact, force: true).perform
  end

  it 'records avatar attempt cooldown after /user/avatar timeout' do
    stub_user_check(exists: true)
    allow(api_client).to receive(:user_info).and_return(
      instance_double(HTTParty::Response, success?: true, parsed_response: { 'data' => { 'Users' => {} } })
    )
    allow(api_client).to receive(:user_avatar).and_raise(
      Custom::Whatsapp::EvolutionGo::ApiError.new(
        'Evolution Go API request failed: POST /user/avatar',
        body: 'Net::ReadTimeout'
      )
    )

    described_class.new(channel: channel, contact: contact, remote_jid: '5511999999999@s.whatsapp.net').perform

    contact.reload
    expect(contact.additional_attributes['evolution_go_avatar_attempted_at']).to be_present
    expect(contact.avatar).not_to be_attached
    expect(described_class.should_enqueue?(contact: contact)).to be(false)
  end

  it 'allows enqueue again after avatar attempt cooldown' do
    contact.update!(
      additional_attributes: {
        'evolution_go_enriched_at' => 1.hour.ago.utc.iso8601(3),
        'evolution_go_avatar_attempted_at' => 7.hours.ago.utc.iso8601(3)
      }
    )

    expect(described_class.should_enqueue?(contact: contact)).to be(true)
  end

  it 'always enqueues when force is true even after a recent avatar attempt' do
    contact.update!(
      additional_attributes: {
        'evolution_go_enriched_at' => Time.current.utc.iso8601(3),
        'evolution_go_avatar_attempted_at' => Time.current.utc.iso8601(3)
      }
    )

    expect(described_class.should_enqueue?(contact: contact, force: true)).to be(true)
  end
end
