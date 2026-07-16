# frozen_string_literal: true

class Custom::Whatsapp::Evolution::ReactSyncService
  ALLOWED_EMOJIS = %w[👍 ❤️ 😂 😮 😢 🙏].freeze

  pattr_initialize [:message!, :reaction!, :user!]

  def perform
    validate!
    response = api_client.send_reaction(
      key: reaction_key,
      reaction: normalized_reaction
    )
    Custom::Whatsapp::Evolution::ApiClient.raise_unless_success!(
      response,
      'Failed to send Evolution reaction'
    )
    apply_local_reaction!
    message
  end

  private

  def validate!
    raise Custom::Whatsapp::Evolution::ApiError, 'Not an Evolution channel' unless evolution_channel?
    raise Custom::Whatsapp::Evolution::ApiError, 'Message source_id is required' if message.source_id.blank?
    raise Custom::Whatsapp::Evolution::ApiError, 'Chat JID is required' if remote_jid.blank?
    raise Custom::Whatsapp::Evolution::ApiError, 'Unsupported reaction' unless allowed_reaction?
  end

  def evolution_channel?
    channel.is_a?(Channel::Whatsapp) && channel.provider == 'evolution'
  end

  def channel
    @channel ||= message.inbox.channel
  end

  def remote_jid
    @remote_jid ||= begin
      attrs = message.content_attributes || {}
      jid = attrs['evolution_remote_jid'].presence || attrs[:evolution_remote_jid].presence
      if jid.present?
        jid
      else
        source_id = message.conversation.contact_inbox.source_id.to_s
        if source_id.include?('@')
          source_id
        else
          phone = source_id.gsub(/\D/, '')
          "#{phone}@s.whatsapp.net"
        end
      end
    end
  end

  def reaction_key
    {
      remoteJid: remote_jid.to_s,
      fromMe: message.outgoing?,
      id: message.source_id.to_s
    }
  end

  def normalized_reaction
    value = reaction.to_s
    return '' if value.blank? || value.casecmp('remove').zero?

    value
  end

  def allowed_reaction?
    normalized_reaction.blank? || ALLOWED_EMOJIS.include?(normalized_reaction)
  end

  def apply_local_reaction!
    actor = Custom::Whatsapp::ReactionsStore.business_actor(actor_id: user.id)
    if normalized_reaction.blank?
      Custom::Whatsapp::ReactionsStore.remove_actor!(
        message,
        actor_key: actor[:actor_key],
        from: actor[:from],
        actor_id: actor[:actor_id]
      )
      return
    end

    Custom::Whatsapp::ReactionsStore.apply!(
      message,
      emoji: normalized_reaction,
      actor_key: actor[:actor_key],
      from: actor[:from],
      actor_id: actor[:actor_id]
    )
  end

  def api_client
    Custom::Whatsapp::Evolution::ApiClient.for_channel(channel)
  end
end
