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
    payload = {
      ignoreGroups: boolean_setting('ignore_groups'),
      rejectCall: boolean_setting('reject_call'),
      alwaysOnline: boolean_setting('always_online'),
      readMessages: boolean_setting('read_messages'),
      ignoreStatus: boolean_setting('ignore_status')
    }.compact

    msg_call = provider_config['msg_call']
    payload[:msgRejectCall] = msg_call.to_s if msg_call.present?
    payload
  end

  def boolean_setting(key)
    return nil if provider_config[key].nil?

    ActiveModel::Type::Boolean.new.cast(provider_config[key])
  end

  def proxy_enabled?
    ActiveModel::Type::Boolean.new.cast(provider_config['proxy_enabled']) &&
      provider_config['proxy_host'].present?
  end
end
