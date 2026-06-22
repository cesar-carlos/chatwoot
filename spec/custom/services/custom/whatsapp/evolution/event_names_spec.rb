# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Whatsapp::Evolution::EventNames do
  describe '.normalize' do
    it 'converts dotted lowercase Evolution events to SCREAMING_SNAKE' do
      expect(described_class.normalize('messages.upsert')).to eq('MESSAGES_UPSERT')
      expect(described_class.normalize('connection.update')).to eq('CONNECTION_UPDATE')
      expect(described_class.normalize('qrcode.updated')).to eq('QRCODE_UPDATED')
    end

    it 'leaves uppercase underscored events unchanged' do
      expect(described_class.normalize('MESSAGES_UPSERT')).to eq('MESSAGES_UPSERT')
    end
  end
end
