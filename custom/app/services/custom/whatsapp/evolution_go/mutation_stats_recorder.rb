# frozen_string_literal: true

class Custom::Whatsapp::EvolutionGo::MutationStatsRecorder
  def self.record!(channel, key)
    config = (channel.provider_config || {}).stringify_keys
    stats = (config['mutation_stats'] || {}).dup
    stats[key.to_s] = stats[key.to_s].to_i + 1
    merged = config.merge('mutation_stats' => stats)
    channel.update_columns(provider_config: merged, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    channel.provider_config = merged
  end
end
