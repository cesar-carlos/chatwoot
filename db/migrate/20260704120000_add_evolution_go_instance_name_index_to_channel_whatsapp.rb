# frozen_string_literal: true

class AddEvolutionGoInstanceNameIndexToChannelWhatsapp < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    return if index_exists?(:channel_whatsapp, name: 'index_channel_whatsapp_evolution_go_instance_name')

    add_index :channel_whatsapp,
              "(provider_config->>'instance_name')",
              unique: true,
              where: "provider = 'evolution_go'",
              name: 'index_channel_whatsapp_evolution_go_instance_name',
              algorithm: :concurrently
  end

  def down
    remove_index :channel_whatsapp, name: 'index_channel_whatsapp_evolution_go_instance_name', if_exists: true
  end
end
