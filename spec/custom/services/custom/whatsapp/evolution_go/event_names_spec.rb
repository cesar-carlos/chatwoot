# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Whatsapp::EvolutionGo::EventNames do
  it 'normalizes PascalCase webhook names to SCREAMING_SNAKE' do
    expect(described_class.normalize('Message')).to eq('MESSAGE')
    expect(described_class.normalize('SendMessage')).to eq('SEND_MESSAGE')
    expect(described_class.normalize('ReadReceipt')).to eq('READ_RECEIPT')
    expect(described_class.normalize('QRCode')).to eq('QRCODE')
  end

  it 'keeps already-normalized names' do
    expect(described_class.normalize('SEND_MESSAGE')).to eq('SEND_MESSAGE')
    expect(described_class.normalize('MESSAGE')).to eq('MESSAGE')
  end
end
