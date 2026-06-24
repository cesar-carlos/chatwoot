# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Whatsapp::Evolution::GroupContactService do
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
        'api_key' => 'TEST-KEY'
      )
    )
  end
  let(:group_jid) { '120363123456789012@g.us' }
  let(:service) { described_class.new(channel: channel, remote_jid: group_jid, push_name: 'Member') }

  before { create(:inbox, account: account, channel: channel) }

  describe '.group_jid?' do
    it 'detects group JIDs' do
      expect(described_class.group_jid?('120363123456789012@g.us')).to be(true)
      expect(described_class.group_jid?('5511999999999@s.whatsapp.net')).to be(false)
    end
  end

  describe '#find_or_create_contact_inbox!' do
    it 'creates a group contact without phone_number and stable source_id' do
      allow(Custom::Whatsapp::Evolution::GroupMetadataService).to receive(:new).and_return(
        instance_double(Custom::Whatsapp::Evolution::GroupMetadataService, display_name: 'Support Team (GROUP)')
      )

      contact_inbox = service.find_or_create_contact_inbox!

      aggregate_failures do
        expect(contact_inbox.source_id).to eq(group_jid)
        expect(contact_inbox.contact.identifier).to eq(group_jid)
        expect(contact_inbox.contact.phone_number).to be_nil
        expect(contact_inbox.contact.name).to eq('Support Team (GROUP)')
        expect(contact_inbox.contact.additional_attributes['is_whatsapp_group']).to be(true)
      end
    end
  end
end
