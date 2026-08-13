# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Contacts::ContactableInboxesService do
  let(:account) { create(:account) }
  let!(:channel) do
    create(
      :channel_whatsapp,
      account: account,
      provider: 'evolution_go',
      sync_templates: false,
      validate_provider_config: false
    )
  end
  let(:inbox) { channel.inbox }

  describe '#get WhatsApp overlay' do
    it 'returns existing group contact_inbox source_id when contact has no phone' do
      group_jid = '120363411111111111@g.us'
      contact = create(
        :contact,
        account: account,
        phone_number: nil,
        identifier: group_jid,
        additional_attributes: { 'is_whatsapp_group' => true }
      )
      create(:contact_inbox, contact: contact, inbox: inbox, source_id: group_jid)

      result = described_class.new(contact: contact).get

      expect(result).to include({ source_id: group_jid, inbox: inbox })
    end

    it 'prefers existing non-phone source_id over phone-derived id' do
      contact = create(:contact, account: account, phone_number: '+5511999999999')
      # Digit-only id that is not the contact phone (LID-like alternate session).
      alternate_source = '5511000000001'
      create(:contact_inbox, contact: contact, inbox: inbox, source_id: alternate_source)

      result = described_class.new(contact: contact).get

      expect(result).to include({ source_id: alternate_source, inbox: inbox })
      expect(result).not_to include({ source_id: contact.phone_number.delete('+'), inbox: inbox })
    end

    it 'falls back to phone-derived source_id when no contact_inbox exists' do
      contact = create(:contact, account: account, phone_number: '+5511888888888')

      result = described_class.new(contact: contact).get

      expect(result).to include({ source_id: contact.phone_number.delete('+'), inbox: inbox })
    end

    it 'returns nothing for WhatsApp when contact has no phone and no contact_inbox' do
      contact = create(:contact, account: account, phone_number: nil, email: nil)

      result = described_class.new(contact: contact).get

      expect(result.pluck(:inbox)).not_to include(inbox)
    end
  end
end
