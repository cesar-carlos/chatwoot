# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ContactInboxBuilder do
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
