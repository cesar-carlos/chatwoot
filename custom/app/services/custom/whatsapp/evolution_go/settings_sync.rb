# frozen_string_literal: true

module Custom::Whatsapp::EvolutionGo::SettingsSync
  def sync_settings!
    instance_id = provider_config['instance_id']
    raise Custom::Whatsapp::EvolutionGo::ApiError, 'instance_id is missing' if instance_id.blank?

    response = api_client.update_advanced_settings(instance_id, settings: advanced_settings_payload)
    Custom::Whatsapp::EvolutionGo::ApiClient.raise_unless_success!(response, 'Failed to sync Evolution Go settings')
  end

  def sync_proxy!
    instance_id = provider_config['instance_id']
    raise Custom::Whatsapp::EvolutionGo::ApiError, 'instance_id is missing' if instance_id.blank?

    if proxy_enabled?
      raise Custom::Whatsapp::EvolutionGo::ApiError,
            'Proxy changes require recreating the Evolution Go instance'
    end

    response = api_client.delete_proxy(instance_id)
    Custom::Whatsapp::EvolutionGo::ApiClient.raise_unless_success!(response, 'Failed to remove Evolution Go proxy')
  end

  private

  def advanced_settings_payload
    {
      ignoreGroups: provider_config['ignore_groups'],
      rejectCall: provider_config['reject_call'],
      msgRejectCall: provider_config['msg_call'].to_s,
      alwaysOnline: provider_config['always_online'],
      readMessages: provider_config['read_messages'],
      ignoreStatus: provider_config['ignore_status']
    }
  end

  def proxy_enabled?
    ActiveModel::Type::Boolean.new.cast(provider_config['proxy_enabled']) &&
      provider_config['proxy_host'].present?
  end
end
