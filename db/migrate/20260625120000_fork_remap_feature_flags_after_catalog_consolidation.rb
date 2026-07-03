# FORK: Fork features were appended after advanced_assignment, pushing it to bit 65 and
# causing PG::NumericValueOutOfRange when saving accounts from Super Admin.
# Consolidate fork flags into repurposed deprecated slots and remap existing bitmasks.
class ForkRemapFeatureFlagsAfterCatalogConsolidation < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    Account.find_each(batch_size: 100) do |account|
      new_flags = remap_feature_flags(account.feature_flags)
      next if new_flags == account.feature_flags

      # rubocop:disable Rails/SkipsModelValidations
      account.update_columns(feature_flags: new_flags, updated_at: Time.current)
      # rubocop:enable Rails/SkipsModelValidations
    end
  end

  private

  def remap_feature_flags(old_value)
    old_value = old_value.to_i
    new_value = old_value & ((1 << 29) - 1)

    # channel_wavoip: position 63 -> 30 (bit 62 -> 29)
    new_value |= (1 << 29) if (old_value & (1 << 62)).nonzero?

    # conversation_agent_no_reply_rules: position 64 -> 31 (bit 63 -> 30)
    new_value |= (1 << 30) if (old_value & (1 << 63)).nonzero?

    # positions 32-62 unchanged (bits 31-61)
    new_value |= (old_value & (((1 << 31) - 1) << 31))

    # advanced_assignment: position 65 -> 63 (bit 64 -> 62)
    new_value |= (1 << 62) if (old_value & (1 << 64)).nonzero?

    new_value
  end
end
