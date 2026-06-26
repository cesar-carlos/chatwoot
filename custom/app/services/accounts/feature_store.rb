# frozen_string_literal: true

# FORK: Dual-read/write feature store to escape the 64-bit feature_flags ceiling.
class Accounts::FeatureStore
  JSONB_PRIMARY_CONFIG = 'FEATURE_FLAGS_JSONB_PRIMARY'
  JSONB_COLUMN = 'enabled_features_data'

  class << self
    def jsonb_column_available?
      Account.column_names.include?(JSONB_COLUMN)
    end

    def jsonb_primary?
      return false unless jsonb_column_available?

      ActiveModel::Type::Boolean.new.cast(
        GlobalConfig.get_value(JSONB_PRIMARY_CONFIG)
      )
    end

    def reconcile_all!
      return 0 unless jsonb_column_available?

      mismatches = 0
      Account.find_each(batch_size: 100) do |account|
        mismatches += 1 if new(account).reconcile!
      end
      mismatches
    end
  end

  def initialize(account)
    @account = account
  end

  def enabled?(feature_name)
    feature_name = feature_name.to_s
    data = jsonb_data

    if data.key?(feature_name)
      return ActiveModel::Type::Boolean.new.cast(data[feature_name])
    end

    return false if self.class.jsonb_primary?

    bitmask_enabled?(feature_name)
  end

  def write(feature_name, value)
    feature_name = feature_name.to_s
    truthy = ActiveModel::Type::Boolean.new.cast(value)
    update_jsonb(feature_name, truthy)
    sync_bitmask(feature_name, truthy) if bitmask_feature?(feature_name)
    truthy
  end

  def bulk_set(selected_flags)
    selected_names = Array(selected_flags).map(&:to_s).map { |flag| flag.delete_prefix('feature_') }.uniq
    catalog_names = catalog_feature_names + jsonb_only_feature_names

    catalog_names.each do |feature_name|
      write(feature_name, selected_names.include?(feature_name))
    end
  end

  def backfill_from_bitmask!
    return unless self.class.jsonb_column_available?

    Featurable::FEATURE_LIST.each do |feature|
      name = feature['name']
      update_jsonb(name, bitmask_enabled?(name))
    end
  end

  def reconcile!
    return false unless self.class.jsonb_column_available?

    changed = false
    Featurable::FEATURE_LIST.each do |feature|
      name = feature['name']
      jsonb_value = jsonb_data[name]
      bitmask_value = bitmask_enabled?(name)
      next if jsonb_value.nil?

      jsonb_bool = ActiveModel::Type::Boolean.new.cast(jsonb_value)
      if jsonb_bool != bitmask_value
        sync_bitmask(name, jsonb_bool)
        changed = true
      end
    end
    changed
  end

  private

  def catalog_feature_names
    Featurable::FEATURE_LIST.pluck('name')
  end

  def jsonb_only_feature_names
    jsonb_data.keys - catalog_feature_names
  end

  def bitmask_feature?(feature_name)
    catalog_feature_names.include?(feature_name.to_s)
  end

  def bitmask_enabled?(feature_name)
    @account.send("feature_#{feature_name}?")
  rescue NoMethodError
    false
  end

  def sync_bitmask(feature_name, truthy)
    @account.send("feature_#{feature_name}=", truthy)
  end

  def jsonb_data
    return {} unless self.class.jsonb_column_available?

    value = @account.public_send(JSONB_COLUMN)
    value.is_a?(Hash) ? value.stringify_keys : {}
  end

  def update_jsonb(feature_name, truthy)
    return unless self.class.jsonb_column_available?

    data = jsonb_data
    data[feature_name] = truthy
    @account.public_send("#{JSONB_COLUMN}=", data)
  end
end
