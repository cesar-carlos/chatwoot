# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Whatsapp::Evolution::GroupParticipantService do
  let(:account) { create(:account) }
  let(:participant_jid) { '551188887777@s.whatsapp.net' }

  before do
    allow(Custom::Whatsapp::EvolutionGo::ContactEnrichmentJob).to receive(:perform_later)
    allow(Custom::Whatsapp::Evolution::ContactEnrichmentJob).to receive(:perform_later)
  end

  def build_channel(provider, config_class)
    config = config_class.build('instance_name' => 'test-instance', 'instance_token' => 'token', 'api_key' => 'token')
    create(
      :channel_whatsapp,
      account: account,
      provider: provider,
      sync_templates: false,
      validate_provider_config: false,
      provider_config: config.except('merge_brazil_contacts')
    )
  end

  it 'merges a legacy Brazil mobile when the Evolution Go key is absent' do
    channel = build_channel('evolution_go', Custom::Whatsapp::EvolutionGo::ProviderConfig)

    described_class.new(channel: channel, participant_jid: participant_jid, push_name: 'Maria').sync!

    expect(account.contacts.find_by(phone_number: '+5511988887777')).to be_present
    expect(account.contacts.find_by(phone_number: '+551188887777')).to be_nil
  end

  it 'leaves a legacy Brazil mobile unchanged for Evolution Node when the key is absent' do
    channel = build_channel('evolution', Custom::Whatsapp::Evolution::ProviderConfig)

    described_class.new(channel: channel, participant_jid: participant_jid, push_name: 'Maria').sync!

    expect(account.contacts.find_by(phone_number: '+551188887777')).to be_present
    expect(account.contacts.find_by(phone_number: '+5511988887777')).to be_nil
  end
end
