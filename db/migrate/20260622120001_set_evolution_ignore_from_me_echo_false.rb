# frozen_string_literal: true

class SetEvolutionIgnoreFromMeEchoFalse < ActiveRecord::Migration[7.1]
  def up
    say_with_time 'Set ignore_from_me_echo to false for existing Evolution inboxes' do
      Channel::Whatsapp.where(provider: 'evolution').find_each do |channel|
        config = (channel.provider_config || {}).stringify_keys
        current = config['ignore_from_me_echo']
        next unless current.nil? || ActiveModel::Type::Boolean.new.cast(current)

        channel.update_column(:provider_config, config.merge('ignore_from_me_echo' => false))
      end
    end
  end

  def down
    # Non-reversible: prior values were true or missing (treated as true in UI).
  end
end
