# frozen_string_literal: true

class Custom::Whatsapp::EvolutionGo::MutationStatsRecorder
  def self.record!(channel, key)
    config = (channel.provider_config || {}).stringify_keys
    stats = (config['mutation_stats'] || {}).dup
    stats[key.to_s] = stats[key.to_s].to_i + 1
    Custom::Whatsapp::EvolutionGo::ProviderConfigMerger.merge!(channel, 'mutation_stats' => stats)
  end
end
