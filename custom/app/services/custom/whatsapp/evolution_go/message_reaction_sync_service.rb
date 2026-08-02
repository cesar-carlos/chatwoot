# frozen_string_literal: true

class Custom::Whatsapp::EvolutionGo::MessageReactionSyncService
  REACTIONS_KEY = Custom::Whatsapp::ReactionsStore::REACTIONS_KEY

  pattr_initialize [:channel!, :data!]

  def perform
    payload = data.with_indifferent_access
    key = (payload[:key] || {}).with_indifferent_access
    return if key[:id].blank?

    message = channel.inbox.messages.find_by(source_id: key[:id])
    if message.blank?
      Custom::Whatsapp::EvolutionGo::MutationStatsRecorder.record!(channel, 'inbound_reaction_skipped')
      return false
    end

    apply_reaction!(message, payload)
    bump_conversation_activity!(message)
    true
  end

  private

  def apply_reaction!(message, payload)
    actor = actor_identity(payload)
    if ActiveModel::Type::Boolean.new.cast(payload[:remove])
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
      emoji: payload[:text].to_s,
      actor_key: actor[:actor_key],
      from: actor[:from],
      actor_id: actor[:actor_id],
      reaction_message_id: payload[:reaction_message_id]
    )
  end

  def bump_conversation_activity!(message)
    conversation = message.conversation
    return if conversation.blank?

    conversation.update_columns(last_activity_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
  end

  def actor_identity(payload)
    from_me = ActiveModel::Type::Boolean.new.cast(payload[:from_me])
    return Custom::Whatsapp::ReactionsStore.business_actor if from_me

    participant = payload[:participant].presence || payload.dig(:key, :participant).presence
    contact = resolve_contact(participant || payload.dig(:key, :remoteJid))
    {
      from: 'contact',
      actor_id: contact&.id,
      actor_key: participant.presence || "contact:#{contact&.id || payload.dig(:key, :remoteJid)}"
    }
  end

  def resolve_contact(jid_or_phone)
    return if jid_or_phone.blank?

    phone = Custom::Whatsapp::EvolutionGo::JidResolver.new(channel.provider_config || {})
                                                      .phone_from_jid(jid_or_phone)
    return if phone.blank?

    channel.inbox.contacts.find_by(phone_number: "+#{phone}") ||
      channel.inbox.contacts.find_by(phone_number: phone)
  end
end
