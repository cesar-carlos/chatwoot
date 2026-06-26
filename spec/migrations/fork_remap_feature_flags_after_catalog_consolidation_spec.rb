require 'rails_helper'
require Rails.root.join('db/migrate/20260625120000_fork_remap_feature_flags_after_catalog_consolidation')

RSpec.describe ForkRemapFeatureFlagsAfterCatalogConsolidation do
  subject(:migration) { described_class.new }

  def remap(old_value)
    migration.send(:remap_feature_flags, old_value)
  end

  it 'moves channel_wavoip from position 63 to 30' do
    old_value = 1 << 62
    new_value = remap(old_value)

    expect(new_value & (1 << 29)).not_to eq(0)
    expect(new_value & (1 << 62)).to eq(0)
  end

  it 'moves conversation_agent_no_reply_rules from position 64 to 31' do
    old_value = 1 << 63
    new_value = remap(old_value)

    expect(new_value & (1 << 30)).not_to eq(0)
    expect(new_value & (1 << 63)).to eq(0)
  end

  it 'moves advanced_assignment from position 65 to 63' do
    old_value = 1 << 64
    new_value = remap(old_value)

    expect(new_value & (1 << 62)).not_to eq(0)
    expect(new_value & (1 << 64)).to eq(0)
  end

  it 'preserves unchanged feature positions' do
    old_value = (1 << 5) | (1 << 40)
    expect(remap(old_value)).to eq(old_value)
  end

  it 'drops deprecated message_reply_to and insert_article_in_reply bits' do
    old_value = (1 << 29) | (1 << 30)
    new_value = remap(old_value)

    expect(new_value & (1 << 29)).to eq(0)
    expect(new_value & (1 << 30)).to eq(0)
  end
end
