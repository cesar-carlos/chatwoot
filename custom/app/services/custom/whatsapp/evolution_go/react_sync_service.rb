# frozen_string_literal: true

class Custom::Whatsapp::EvolutionGo::ReactSyncService
  REACTIONS_KEY = Custom::Whatsapp::ReactionsStore::REACTIONS_KEY
  ALLOWED_EMOJIS = %w[👍 ❤️ 😂 😮 😢 🙏].freeze

  pattr_initialize [:message!, :reaction!, :user!]

  def perform
    validate!
    response = api_client.react(
      number: chat_jid,
      id: message.source_id,
      reaction: normalized_reaction,
      from_me: message.outgoing?,
      participant: group_participant
    )
    Custom::Whatsapp::EvolutionGo::ApiClient.raise_unless_success!(
      response,
      'Failed to send Evolution Go reaction'
    )
    apply_local_reaction!
    message
  end

  private

  def validate!
    raise Custom::Whatsapp::EvolutionGo::ApiError, 'Not an Evolution Go channel' unless evolution_go_channel?
    raise Custom::Whatsapp::EvolutionGo::ApiError, 'Message source_id is required' if message.source_id.blank?
    raise Custom::Whatsapp::EvolutionGo::ApiError, 'Cannot react to a private note' if message.private?
    raise Custom::Whatsapp::EvolutionGo::ApiError, 'Cannot react to a deleted message' if message_deleted?
    raise Custom::Whatsapp::EvolutionGo::ApiError, 'Chat JID is required' if chat_jid.blank?
    raise Custom::Whatsapp::EvolutionGo::ApiError, 'Unsupported reaction' unless allowed_reaction?
  end

  def message_deleted?
    ActiveModel::Type::Boolean.new.cast(message.content_attributes&.[]('deleted')) ||
      ActiveModel::Type::Boolean.new.cast(message.content_attributes&.[](:deleted))
  end

  def evolution_go_channel?
    channel.is_a?(Channel::Whatsapp) && channel.provider == 'evolution_go'
  end

  def channel
    @channel ||= message.inbox.channel
  end

  def chat_jid
    @chat_jid ||= Custom::Whatsapp::EvolutionGo::ChatJid.for_message(message)
  end

  def normalized_reaction
    value = reaction.to_s
    return '' if value.blank? || value.casecmp('remove').zero?

    value
  end

  def allowed_reaction?
    normalized_reaction.blank? || ALLOWED_EMOJIS.include?(normalized_reaction)
  end

  def group_participant
    return unless chat_jid.to_s.include?('@g.us')

    message.content_attributes&.dig('evolution_go_participant_jid').presence
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
    Custom::Whatsapp::EvolutionGo::ApiClient.for_channel(channel)
  end
end
