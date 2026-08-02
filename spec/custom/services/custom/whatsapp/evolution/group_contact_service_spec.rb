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

    it 'does not overwrite a confirmed group name with a member pushName fallback' do
      create(
        :contact,
        account: account,
        identifier: group_jid,
        name: 'Support Team (GROUP)',
        phone_number: nil,
        additional_attributes: {
          'is_whatsapp_group' => true,
          'evolution_group_jid' => group_jid
        }
      )
      allow(Custom::Whatsapp::Evolution::GroupMetadataService).to receive(:new).and_return(
        instance_double(Custom::Whatsapp::Evolution::GroupMetadataService, display_name: 'Member')
      )

      contact_inbox = service.find_or_create_contact_inbox!

      expect(contact_inbox.contact.reload.name).to eq('Support Team (GROUP)')
    end

    it 'updates the contact name when metadata returns a confirmed GROUP name' do
      create(
        :contact,
        account: account,
        identifier: group_jid,
        name: 'Member',
        phone_number: nil,
        additional_attributes: {
          'is_whatsapp_group' => true,
          'evolution_group_jid' => group_jid
        }
      )
      allow(Custom::Whatsapp::Evolution::GroupMetadataService).to receive(:new).and_return(
        instance_double(Custom::Whatsapp::Evolution::GroupMetadataService, display_name: 'Support Team (GROUP)')
      )

      contact_inbox = service.find_or_create_contact_inbox!

      expect(contact_inbox.contact.reload.name).to eq('Support Team (GROUP)')
    end

    it 'does not seed the contact name from member pushName on create' do
      metadata = instance_double(Custom::Whatsapp::Evolution::GroupMetadataService)
      allow(Custom::Whatsapp::Evolution::GroupMetadataService).to receive(:new)
        .with(channel: channel)
        .and_return(metadata)
      expect(metadata).to receive(:display_name).with(group_jid, fallback: nil)
                                                .and_return('120363123456789012')

      contact_inbox = service.find_or_create_contact_inbox!

      expect(contact_inbox.contact.name).to eq('120363123456789012')
      expect(contact_inbox.contact.name).not_to eq('Member')
    end
  end
end
