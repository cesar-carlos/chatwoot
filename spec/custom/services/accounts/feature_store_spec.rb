# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Accounts::FeatureStore do
  let(:account) { create(:account) }

  before do
    skip 'enabled_features_data column is not available' unless described_class.jsonb_column_available?
  end

  describe '#write and #enabled?' do
    it 'persists catalog features in jsonb and bitmask' do
      store = described_class.new(account)
      store.write('custom_tools', true)
      account.save!

      account.reload
      expect(described_class.new(account).enabled?('custom_tools')).to be(true)
      expect(account.feature_enabled?('custom_tools')).to be(true)
    end
  end

  describe '#bulk_set' do
    it 'replaces the enabled feature set' do
      account.enable_features!('custom_tools', 'macros')

      described_class.new(account).bulk_set([:feature_macros])
      account.save!

      account.reload
      expect(account.feature_enabled?('macros')).to be(true)
      expect(account.feature_enabled?('custom_tools')).to be(false)
    end
  end

  describe '#backfill_from_bitmask!' do
    it 'copies legacy bitmask values into jsonb' do
      account.enable_features!('assignment_v2')
      store = described_class.new(account)
      store.backfill_from_bitmask!
      account.save!

      expect(account.enabled_features_data['assignment_v2']).to be(true)
    end
  end

  describe '.reconcile_all!' do
    it 'returns zero when jsonb and bitmask are aligned' do
      account.enable_features!('sla')
      described_class.new(account).backfill_from_bitmask!
      account.save!

      expect(described_class.reconcile_all!).to eq(0)
    end
  end
end
