# frozen_string_literal: true

module Custom::Concerns::Featurable
  def enable_features(*names)
    return super unless Accounts::FeatureStore.jsonb_column_available?

    names.each { |name| feature_store.write(name, true) }
  end

  def disable_features(*names)
    return super unless Accounts::FeatureStore.jsonb_column_available?

    names.each { |name| feature_store.write(name, false) }
  end

  def feature_enabled?(name)
    return super unless Accounts::FeatureStore.jsonb_column_available?

    feature_store.enabled?(name)
  end

  private

  def feature_store
    @feature_store ||= Accounts::FeatureStore.new(self)
  end
end

Featurable.prepend_mod_with('Concerns::Featurable')
