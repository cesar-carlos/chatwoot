# frozen_string_literal: true

class Custom::Whatsapp::Evolution::DeleteSyncService
  pattr_initialize [:message!]

  def perform
    return unless evolution_channel?
    return unless sync_delete_enabled?
    return if message.source_id.blank?

    api_client.delete_message_for_everyone(
      id: message.source_id,
      remote_jid: remote_jid,
      from_me: !message.incoming?
    ).tap do |response|
      unless response.success?
        Rails.logger.warn(
          "[EVOLUTION] delete sync HTTP #{response.code} for message #{message.id}"
        )
      end
    end
  rescue StandardError => e
    Rails.logger.warn "[EVOLUTION] delete sync failed for message #{message.id}: #{e.message}"
  end

  private

  def evolution_channel?
    channel.is_a?(Channel::Whatsapp) && channel.provider == 'evolution'
  end

  def channel
    @channel ||= message.inbox.channel
  end

  def sync_delete_enabled?
    ActiveModel::Type::Boolean.new.cast((channel.provider_config || {})['sync_delete_to_whatsapp'])
  end

  def remote_jid
    phone = message.conversation.contact_inbox.source_id.to_s.gsub(/\D/, '')
    "#{phone}@s.whatsapp.net"
  end

  def api_client
    config = channel.provider_config || {}
    Custom::Whatsapp::Evolution::ApiClient.new(
      base_url: config['base_url'],
      api_key: config['api_key'],
      instance_name: config['instance_name']
    )
  end
end
