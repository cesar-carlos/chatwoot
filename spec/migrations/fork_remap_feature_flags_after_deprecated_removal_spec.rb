require 'rails_helper'
require Rails.root.join('db/migrate/20260626120000_fork_remap_feature_flags_after_deprecated_removal')

RSpec.describe ForkRemapFeatureFlagsAfterDeprecatedRemoval do
  subject(:migration) { described_class.new }

  let(:old_names) { described_class::OLD_FEATURE_NAMES }
  let(:new_names) { described_class::NEW_FEATURE_NAMES }

  def decode(value, names)
    names.each_with_index.with_object({}) do |(name, index), result|
      result[name] = (value.to_i & (1 << index)).nonzero?
    end
  end

  def encode(enabled_by_name, names)
    names.each_with_index.sum do |name, index|
      enabled_by_name[name] ? (1 << index) : 0
    end
  end

  it 'drops deprecated feature bits while preserving active features' do
    enabled = decode(0, old_names)
    enabled['whatsapp_embedded_signup'] = true
    enabled['assignment_v2'] = true
    old_value = encode(enabled, old_names)
    new_value = encode(decode(old_value, old_names), new_names)

    expect(new_value & (1 << new_names.index('assignment_v2'))).not_to eq(0)
    expect(new_names).not_to include('whatsapp_embedded_signup', 'quoted_email_reply')
  end

  it 'preserves unchanged features across remap' do
    enabled = decode(0, old_names)
    enabled['custom_tools'] = true
    enabled['advanced_assignment'] = true
    old_value = encode(enabled, old_names)
    remapped_enabled = decode(old_value, old_names)

    new_value = encode(remapped_enabled, new_names)
    expect(new_value & (1 << new_names.index('custom_tools'))).not_to eq(0)
    expect(new_value & (1 << new_names.index('advanced_assignment'))).not_to eq(0)
  end
end
