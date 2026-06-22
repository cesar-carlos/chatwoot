# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Whatsapp::Evolution::ContactEnrichmentService do
  let(:account) { create(:account) }
  let(:channel) do
    create(
      :channel_whatsapp,
      account: account,
      provider: 'evolution',
      sync_templates: false,
      validate_provider_config: false,
      provider_config: Custom::Whatsapp::Evolution::ProviderConfig.build(
        'instance_name' => 'test-instance',
        'api_key' => 'TEST-KEY',
        'base_url' => 'http://localhost:8080'
      )
    )
  end
  let(:contact) do
    create(
      :contact,
      account: account,
      name: '+556696971841',
      phone_number: '+556696971841'
    )
  end
  let(:api_client) { instance_double(Custom::Whatsapp::Evolution::ApiClient) }

  before do
    allow(Custom::Whatsapp::Evolution::ApiClient).to receive(:for_channel).and_return(api_client)
    allow(api_client).to receive(:fetch_profile).and_return(
      instance_double(HTTParty::Response, success?: false)
    )
    allow(api_client).to receive(:fetch_profile_picture_url).and_return(
      instance_double(HTTParty::Response, success?: false)
    )
    allow(Avatar::AvatarFromUrlJob).to receive(:perform_later)
  end

  it 'persists remote JID and updates name from pushName' do
    described_class.new(
      channel: channel,
      contact: contact,
      remote_jid: '242532642504895@lid',
      push_name: 'Matheus Teixeira'
    ).perform

    contact.reload
    expect(contact.identifier).to eq('242532642504895@lid')
    expect(contact.name).to eq('Matheus Teixeira')
    expect(contact.additional_attributes['evolution_remote_jid']).to eq('242532642504895@lid')
    expect(contact.additional_attributes['evolution_push_name']).to eq('Matheus Teixeira')
  end

  it 'queues avatar download when profilePicUrl is provided' do
    described_class.new(
      channel: channel,
      contact: contact,
      profile_pic_url: 'https://pps.whatsapp.net/v/example.jpg'
    ).perform

    expect(Avatar::AvatarFromUrlJob).to have_received(:perform_later).with(
      contact,
      'https://pps.whatsapp.net/v/example.jpg'
    )
  end

  it 'applies profile and business data from fetchProfile' do
    allow(api_client).to receive(:fetch_profile).and_return(
      instance_double(
        HTTParty::Response,
        success?: true,
        parsed_response: {
          'name' => 'Business Name',
          'status' => 'Available',
          'isBusiness' => true,
          'profilePictureUrl' => 'https://pps.whatsapp.net/v/profile.jpg',
          'businessProfile' => {
            'email' => 'biz@example.com',
            'description' => 'We sell things',
            'website' => ['https://example.com'],
            'address' => 'Sao Paulo',
            'category' => 'Retail'
          }
        }
      )
    )

    described_class.new(channel: channel, contact: contact, remote_jid: '556696971841@s.whatsapp.net').perform

    contact.reload
    expect(contact.name).to eq('Business Name')
    expect(contact.email).to eq('biz@example.com')
    expect(contact.location).to eq('Sao Paulo')
    expect(contact.custom_attributes['whatsapp_status']).to eq('Available')
    expect(contact.custom_attributes['whatsapp_business']).to be(true)
    expect(contact.custom_attributes['business_category']).to eq('Retail')
    expect(contact.additional_attributes['company_website']).to eq('https://example.com')
  end

  it 'uses full JID for profile lookup on LID contacts' do
    allow(api_client).to receive(:fetch_profile).and_return(
      instance_double(HTTParty::Response, success?: false)
    )

    described_class.new(
      channel: channel,
      contact: contact,
      remote_jid: '242532642504895@lid'
    ).perform

    expect(api_client).to have_received(:fetch_profile).with(number: '242532642504895@lid')
  end
end
