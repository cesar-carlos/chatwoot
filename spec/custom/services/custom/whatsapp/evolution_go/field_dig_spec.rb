# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Whatsapp::EvolutionGo::FieldDig do
  describe '.dig_field' do
    it 'preserves explicit false and zero values' do
      hash = { 'Connected' => true, 'loggedIn' => false, 'retryCount' => 0 }

      expect(described_class.dig_field(hash, 'connected', 'Connected')).to be(true)
      expect(described_class.dig_field(hash, 'loggedIn', 'LoggedIn')).to be(false)
      expect(described_class.dig_field(hash, 'retryCount', 'RetryCount')).to eq(0)
    end
  end
end
