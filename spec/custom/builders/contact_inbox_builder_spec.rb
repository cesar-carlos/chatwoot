# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ContactInboxBuilder do
  describe 'whatsapp inbox' do
    let(:account) { create(:account) }

    it 'does not rewrite a whatsapp source id owned by another contact' do
      whatsapp_inbox = create(
        :channel_whatsapp,
        account: account,
        sync_templates: false,
        validate_provider_config: false
      ).inbox
      owner = create(:contact, account: account, phone_number: '+554399845097')
      incoming = create(:contact, account: account, phone_number: '+5543999845097')
      contact_inbox = create(:contact_inbox, contact: owner, inbox: whatsapp_inbox, source_id: '5543999845097')

      expect do
        described_class.new(contact: incoming, inbox: whatsapp_inbox, source_id: '5543999845097').perform
      end.to raise_error(ActiveRecord::RecordNotUnique)

      expect(contact_inbox.reload.source_id).to eq('5543999845097')
      expect(contact_inbox.contact_id).to eq(owner.id)
    end
  end

  describe 'wavoip inbox' do
    let(:account) { create(:account) }
    let(:contact) { create(:contact, phone_number: '+5566999050319', account: account) }
    let(:channel) { create(:channel_wavoip, account: account) }
    let(:inbox) { channel.inbox }

    it 'creates contact inbox with phone source id without plus prefix' do
      contact_inbox = described_class.new(contact: contact, inbox: inbox).perform

      expect(contact_inbox.source_id).to eq('5566999050319')
    end
  end
end
