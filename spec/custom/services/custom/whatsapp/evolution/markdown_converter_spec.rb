# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Whatsapp::Evolution::MarkdownConverter do
  describe '.outbound' do
    it 'converts Chatwoot bold to WhatsApp bold' do
      expect(described_class.outbound('**hello**')).to eq('*hello*')
    end

    it 'converts Chatwoot italic to WhatsApp italic' do
      expect(described_class.outbound('*hello*')).to eq('_hello_')
    end

    it 'returns blank input unchanged' do
      expect(described_class.outbound('')).to eq('')
      expect(described_class.outbound(nil)).to be_nil
    end
  end

  describe '.inbound' do
    it 'converts WhatsApp bold to Chatwoot bold' do
      expect(described_class.inbound('*hello*')).to eq('**hello**')
    end

    it 'converts WhatsApp italic to Chatwoot italic' do
      expect(described_class.inbound('_hello_')).to eq('*hello*')
    end
  end
end
