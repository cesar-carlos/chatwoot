# frozen_string_literal: true

class AddEvolutionInstanceNameIndexToChannelWhatsapp < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    add_index :channel_whatsapp,
              "(provider_config->>'instance_name')",
              unique: true,
              where: "provider = 'evolution'",
              name: 'index_channel_whatsapp_evolution_instance_name',
              algorithm: :concurrently
  end

  def down
    remove_index :channel_whatsapp, name: 'index_channel_whatsapp_evolution_instance_name'
  end
end
