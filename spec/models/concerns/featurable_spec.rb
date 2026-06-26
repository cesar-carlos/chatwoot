require 'rails_helper'

RSpec.describe Featurable do
  describe 'feature catalog' do
    it 'keeps the catalog within bigint capacity' do
      expect(Featurable::FEATURE_LIST.size).to be <= 64
    end
  end

  describe 'persisting high-index features' do
    let(:account) { create(:account) }

    it 'persists advanced_assignment without overflow' do
      account.enable_features('advanced_assignment')
      expect { account.save! }.not_to raise_error
      expect(account.reload.feature_enabled?('advanced_assignment')).to be(true)
    end
  end
end
