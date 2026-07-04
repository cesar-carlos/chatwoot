# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Channels::OutboundText do
  describe '.allowed?' do
    it 'returns false for Wavoip channel' do
      channel = build(:channel_wavoip)

      expect(described_class.allowed?(channel)).to be false
    end

    it 'returns true for channels without explicit override' do
      channel = build(:channel_api)

      expect(described_class.allowed?(channel)).to be true
    end
  end
end
