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

    described_class.new(channel: channel, contact: contact, force: false).perform

    expect(contact.reload.avatar).not_to be_attached
  end

  it 'downloads avatar inline on force when avatar response contains an HTTP URL' do
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
    expect(Avatar::AvatarFromUrlJob).to receive(:perform_now).with(contact, 'https://cdn.example.com/avatar.jpg')

    described_class.new(channel: channel, contact: contact, force: true).perform
  end

  it 'retries /user/avatar on timeout when force is true' do
    stub_user_check(exists: true)
    allow(api_client).to receive(:user_info).and_return(
      instance_double(HTTParty::Response, success?: true, parsed_response: { 'data' => { 'Users' => {} } })
    )
    allow(Kernel).to receive(:sleep)

    call_count = 0
    allow(api_client).to receive(:user_avatar) do
      call_count += 1
      raise Custom::Whatsapp::EvolutionGo::ApiError, 'POST /user/avatar: Net::ReadTimeout' if call_count < 3

      instance_double(
        HTTParty::Response,
        success?: true,
        parsed_response: { 'data' => { 'url' => 'https://cdn.example.com/retry-avatar.jpg' } }
      )
    end
    expect(Avatar::AvatarFromUrlJob).to receive(:perform_now).with(contact, 'https://cdn.example.com/retry-avatar.jpg')

    described_class.new(
      channel: channel,
      contact: contact,
      remote_jid: '5511999999999@s.whatsapp.net',
      force: true
    ).perform
  end

  it 'applies short timeout cooldown after /user/avatar network timeout' do
    stub_user_check(exists: true)
    allow(api_client).to receive(:user_info).and_return(
      instance_double(HTTParty::Response, success?: true, parsed_response: { 'data' => { 'Users' => {} } })
    )
    allow(api_client).to receive(:user_avatar).and_raise(
      Custom::Whatsapp::EvolutionGo::ApiError.new(
        'Evolution Go API request failed: POST /user/avatar: Net::ReadTimeout with #<TCPSocket:(closed)>'
      )
    )

    described_class.new(channel: channel, contact: contact, remote_jid: '5511999999999@s.whatsapp.net').perform

    contact.reload
    expect(contact.additional_attributes['evolution_go_avatar_attempted_at']).to be_blank
    expect(contact.additional_attributes['evolution_go_avatar_timeout_at']).to be_present
    expect(contact.avatar).not_to be_attached
    # Short backoff — not enqueueable immediately (unlike previous no-cooldown behavior)
    expect(described_class.should_enqueue?(contact: contact)).to be(false)
  end

  it 'allows enqueue again after avatar timeout cooldown' do
    contact.update!(
      additional_attributes: {
        'evolution_go_enriched_at' => 1.hour.ago.utc.iso8601(3),
        'evolution_go_avatar_timeout_at' => 31.minutes.ago.utc.iso8601(3)
      }
    )

    expect(described_class.should_enqueue?(contact: contact)).to be(true)
  end

  it 'queries /user/avatar with LID before phone digits' do
    contact.update!(
      identifier: '279224615219224@lid',
      additional_attributes: { 'evolution_go_remote_jid' => '5511999999999@s.whatsapp.net' }
    )
    stub_user_check(exists: true)
    allow(api_client).to receive(:user_info).and_return(
      instance_double(HTTParty::Response, success?: true, parsed_response: { 'data' => { 'Users' => {} } })
    )
    expect(api_client).to receive(:user_avatar).with(number: '279224615219224@lid', preview: true).and_return(
      instance_double(
        HTTParty::Response,
        success?: true,
        parsed_response: { 'data' => { 'url' => 'https://cdn.example.com/lid-avatar.jpg' } }
      )
    )
    expect(Avatar::AvatarFromUrlJob).to receive(:perform_now).with(contact, 'https://cdn.example.com/lid-avatar.jpg')

    described_class.new(channel: channel, contact: contact, force: true).perform
  end

  it 'falls back to PN jid when LID avatar times out' do
    contact.update!(identifier: '279224615219224@lid')
    stub_user_check(exists: true)
    allow(api_client).to receive(:user_info).and_return(
      instance_double(HTTParty::Response, success?: true, parsed_response: { 'data' => { 'Users' => {} } })
    )
    allow(Kernel).to receive(:sleep)
    allow(api_client).to receive(:user_avatar).with(number: '279224615219224@lid', preview: true).and_raise(
      Custom::Whatsapp::EvolutionGo::ApiError.new(
        'Evolution Go API request failed: POST /user/avatar: Net::ReadTimeout'
      )
    )
    expect(api_client).to receive(:user_avatar)
      .with(number: '5511999999999@s.whatsapp.net', preview: true)
      .and_return(
        instance_double(
          HTTParty::Response,
          success?: true,
          parsed_response: { 'data' => { 'url' => 'https://cdn.example.com/pn-avatar.jpg' } }
        )
      )
    expect(Avatar::AvatarFromUrlJob).to receive(:perform_now).with(contact, 'https://cdn.example.com/pn-avatar.jpg')

    described_class.new(
      channel: channel,
      contact: contact,
      remote_jid: '5511999999999@s.whatsapp.net',
      force: true
    ).perform
  end

  it 'does not stamp 6h cooldown when LID returns empty and PN times out' do
    contact.update!(identifier: '279224615219224@lid')
    stub_user_check(exists: true)
    allow(api_client).to receive(:user_info).and_return(
      instance_double(HTTParty::Response, success?: true, parsed_response: { 'data' => { 'Users' => {} } })
    )
    allow(api_client).to receive(:user_avatar).with(number: '279224615219224@lid', preview: true).and_return(
      instance_double(HTTParty::Response, success?: true, parsed_response: { 'data' => {} })
    )
    allow(api_client).to receive(:user_avatar).with(number: '5511999999999@s.whatsapp.net', preview: true).and_raise(
      Custom::Whatsapp::EvolutionGo::ApiError.new(
        'Evolution Go API request failed: POST /user/avatar: Net::ReadTimeout'
      )
    )

    described_class.new(
      channel: channel,
      contact: contact,
      remote_jid: '5511999999999@s.whatsapp.net'
    ).perform

    contact.reload
    expect(contact.additional_attributes['evolution_go_avatar_attempted_at']).to be_blank
    expect(contact.additional_attributes['evolution_go_avatar_timeout_at']).to be_present
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

  it 'queries /user/info with digits only and applies status/LID from filled Users payload' do
    stub_user_check(exists: true)
    allow(api_client).to receive(:user_info).with(numbers: ['5511999999999']).and_return(
      instance_double(
        HTTParty::Response,
        success?: true,
        parsed_response: {
          'data' => {
            'Users' => {
              '5511999999999@s.whatsapp.net' => {
                'Status' => 'Available',
                'PictureID' => '1',
                'PictureURL' => 'https://cdn.example.com/from-info.jpg',
                'LID' => '123456789012345@lid',
                'Devices' => ['5511999999999@s.whatsapp.net']
              }
            }
          },
          'message' => 'success'
        }
      )
    )
    allow(api_client).to receive(:user_avatar).and_return(
      instance_double(
        HTTParty::Response,
        success?: true,
        parsed_response: { 'data' => { 'url' => 'https://cdn.example.com/avatar.jpg' } }
      )
    )
    allow(Avatar::AvatarFromUrlJob).to receive(:perform_now)

    described_class.new(channel: channel, contact: contact, force: true).perform

    contact.reload
    expect(contact.custom_attributes['whatsapp_status']).to eq('Available')
    expect(contact.identifier).to eq('123456789012345@lid')
    expect(contact.additional_attributes['evolution_go_remote_jid']).to eq('5511999999999@s.whatsapp.net')
  end

  it 'retries /user/info with digits when phone@s.whatsapp.net returns empty Users fields' do
    stub_user_check(exists: true)
    allow(api_client).to receive(:user_info).with(numbers: ['5511999999999@s.whatsapp.net']).and_return(
      instance_double(
        HTTParty::Response,
        success?: true,
        parsed_response: {
          'data' => {
            'Users' => {
              '5511999999999@s.whatsapp.net' => {
                'Status' => '',
                'PictureID' => '',
                'PictureURL' => '',
                'Devices' => []
              }
            }
          },
          'message' => 'success'
        }
      )
    )
    allow(api_client).to receive(:user_info).with(numbers: ['5511999999999']).and_return(
      instance_double(
        HTTParty::Response,
        success?: true,
        parsed_response: {
          'data' => {
            'Users' => {
              '5511999999999@s.whatsapp.net' => {
                'Status' => 'Hello',
                'LID' => '999@lid',
                'Devices' => ['5511999999999@s.whatsapp.net']
              }
            }
          },
          'message' => 'success'
        }
      )
    )
    allow(api_client).to receive(:user_avatar).and_return(
      instance_double(HTTParty::Response, success?: true, parsed_response: { 'data' => {} })
    )

    described_class.new(
      channel: channel,
      contact: contact,
      remote_jid: '5511999999999@s.whatsapp.net',
      force: true
    ).perform

    expect(contact.reload.custom_attributes['whatsapp_status']).to eq('Hello')
  end

  it 'falls back to PictureURL from /user/info when /user/avatar is privacy-blocked' do
    stub_user_check(exists: true)
    allow(api_client).to receive(:user_info).and_return(
      instance_double(
        HTTParty::Response,
        success?: true,
        parsed_response: {
          'data' => {
            'Users' => {
              '5511999999999@s.whatsapp.net' => {
                'Status' => 'x',
                'PictureID' => '42',
                'PictureURL' => '',
                'Devices' => ['5511999999999@s.whatsapp.net']
              }
            }
          }
        }
      )
    )
    allow(api_client).to receive(:user_avatar).and_return(
      instance_double(
        HTTParty::Response,
        success?: false,
        code: 500,
        parsed_response: { 'error' => 'the user has hidden their profile picture from you' }
      )
    )
    expect(Avatar::AvatarFromUrlJob).not_to receive(:perform_later)

    described_class.new(channel: channel, contact: contact, force: true).perform
  end

  it 'uses PictureURL from /user/info and skips /user/avatar when URL is present' do
    allow(api_client).to receive(:user_info).and_return(
      instance_double(
        HTTParty::Response,
        success?: true,
        parsed_response: {
          'data' => {
            'Users' => {
              '5511999999999@s.whatsapp.net' => {
                'Status' => 'Hello',
                'PictureID' => '99',
                'PictureURL' => 'https://cdn.example.com/info-pic.jpg',
                'Devices' => ['5511999999999@s.whatsapp.net']
              }
            }
          }
        }
      )
    )
    expect(api_client).not_to receive(:user_check)
    expect(api_client).not_to receive(:user_avatar)
    expect(Avatar::AvatarFromUrlJob).to receive(:perform_now).with(contact, 'https://cdn.example.com/info-pic.jpg')

    described_class.new(channel: channel, contact: contact, force: true).perform

    expect(contact.reload.additional_attributes['evolution_go_picture_id']).to eq('99')
    expect(contact.custom_attributes['whatsapp_status']).to eq('Hello')
  end

  it 'does not mark enriched_at when /user/info is rate-limited' do
    allow(api_client).to receive(:user_info).and_return(
      instance_double(
        HTTParty::Response,
        success?: false,
        code: 500,
        parsed_response: { 'error' => 'failed to send usync query: info query returned status 429: rate-overlimit' }
      )
    )
    expect(api_client).not_to receive(:user_avatar)

    described_class.new(channel: channel, contact: contact, force: true).perform

    expect(contact.reload.additional_attributes['evolution_go_enriched_at']).to be_blank
  end

  it 'does not start avatar cooldown on rate-overlimit from /user/avatar' do
    stub_user_check(exists: true)
    allow(api_client).to receive(:user_info).and_return(
      instance_double(HTTParty::Response, success?: true, parsed_response: { 'data' => { 'Users' => {} } })
    )
    allow(api_client).to receive(:user_avatar).and_return(
      instance_double(
        HTTParty::Response,
        success?: false,
        code: 500,
        parsed_response: { 'error' => 'failed to send usync query: info query returned status 429: rate-overlimit' }
      )
    )

    described_class.new(channel: channel, contact: contact, force: true).perform

    expect(contact.reload.additional_attributes['evolution_go_avatar_attempted_at']).to be_blank
    expect(contact.additional_attributes['evolution_go_enriched_at']).to be_blank
  end

  it 'delegates WhatsApp group contacts to GroupMetadataService' do
    group_jid = '120363012345678901@g.us'
    group_contact = create(
      :contact,
      account: account,
      phone_number: nil,
      identifier: group_jid,
      name: 'Old Name (GROUP)',
      additional_attributes: {
        Custom::Whatsapp::Evolution::GroupKeys::IS_WHATSAPP_GROUP_KEY => true,
        Custom::Whatsapp::Evolution::GroupKeys::EVOLUTION_GROUP_JID_KEY => group_jid
      }
    )
    metadata = instance_double(Custom::Whatsapp::Evolution::GroupMetadataService)
    allow(Custom::Whatsapp::Evolution::GroupMetadataService).to receive(:new)
      .with(channel: channel)
      .and_return(metadata)

    expect(metadata).to receive(:warm_cache!).with(group_jid)
    expect(api_client).not_to receive(:user_info)

    described_class.new(channel: channel, contact: group_contact, force: true).perform
  end
end
