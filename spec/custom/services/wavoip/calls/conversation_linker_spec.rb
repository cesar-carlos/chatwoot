# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Wavoip::Calls::ConversationLinker do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_wavoip, account: account) }
  let(:inbox) { channel.inbox }
  let(:caller_phone) { '+5511888888888' }
  let(:provider_call_id) { 'wavoip_source_id_reuse_001' }

  before do
    account.enable_features!('channel_voice', 'channel_wavoip')
  end

  def build_event(overrides = {})
    defaults = {
      provider: :wavoip,
      external_call_id: provider_call_id,
      action: :create,
      external_status: 'INCOMING_RING',
      direction: :incoming,
      from_phone: caller_phone,
      to_phone: channel.phone_number,
      peer_name: 'Inbound Caller',
      duration_seconds: nil,
      session_id: 12_345,
      call_type: :official,
      record_url: nil,
      record_status: nil,
      raw_type: 'CALL'
    }
    Voice::Dto::WebhookCallEvent.new(**defaults, **overrides)
  end

  describe 'source_id normalization' do
    it 'reuses contact_inbox created by outbound path when inbound webhook arrives' do
      outbound_event = build_event(
        direction: :outgoing,
        from_phone: caller_phone,
        to_phone: channel.phone_number,
        external_call_id: 'wavoip_outbound_first',
        external_status: 'OUTGOING_RING'
      )
      outbound = described_class.link!(inbox: inbox, event: outbound_event)
      outbound_source_id = caller_phone.delete_prefix('+')

      inbound = described_class.link_inbound!(inbox: inbox, event: build_event)

      aggregate_failures do
        expect(outbound.contact.contact_inboxes.find_by(inbox: inbox).source_id).to eq(outbound_source_id)
        expect(inbox.contact_inboxes.where(source_id: outbound_source_id).count).to eq(1)
        expect(inbound.contact_id).to eq(outbound.contact_id)
      end
    end

    it 'reuses contact_inbox seeded with digits-only source_id from UI/outbound flows' do
      contact = create(:contact, phone_number: caller_phone, account: account)
      ContactInbox.create!(
        contact: contact,
        inbox: inbox,
        source_id: caller_phone.delete_prefix('+')
      )

      inbound = described_class.link_inbound!(inbox: inbox, event: build_event)

      aggregate_failures do
        expect(inbound.contact_id).to eq(contact.id)
        expect(inbox.contact_inboxes.where(source_id: caller_phone.delete_prefix('+')).count).to eq(1)
      end
    end
  end
end
