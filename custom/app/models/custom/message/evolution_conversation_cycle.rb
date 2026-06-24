# frozen_string_literal: true

# Overrides Message#reopen_conversation to implement Evolution's pending-cycle flow.
# When conversation_pending is enabled, resolved/snoozed conversations reopen as
# "pending" (not "open") and stay pending until a second inbound message arrives.
module Custom::Message::EvolutionConversationCycle
  private

  def reopen_conversation
    return if history_import_message?
    return if conversation.muted?
    return unless incoming?
    return if conversation.open?

    if conversation.inbox.lock_to_single_conversation?
      reopen_inactive_conversation
    elsif evolution_pending_reopen?
      reopen_evolution_without_single_history
    else
      super
    end
  end

  def reopen_evolution_without_single_history
    if conversation.resolved?
      reopen_resolved_conversation
    elsif conversation.snoozed?
      activate_from_snoozed!
    elsif conversation.pending?
      open_evolution_pending_cycle_if_needed
    end
  end

  def reopen_inactive_conversation
    if conversation.resolved?
      reopen_resolved_conversation
    elsif conversation.snoozed?
      activate_from_snoozed!
    elsif conversation.pending?
      open_evolution_pending_cycle_if_needed
    end
  end

  def reopen_resolved_conversation
    return if history_import_message?

    if evolution_pending_reopen?
      conversation.pending!
      stamp_evolution_pending_cycle!
      return
    end

    super
  end

  def activate_from_snoozed!
    if evolution_pending_reopen?
      conversation.pending!
      stamp_evolution_pending_cycle!
    else
      conversation.open!
    end
  end

  def open_evolution_pending_cycle_if_needed
    return if first_incoming_in_pending_cycle?

    conversation.open!
    clear_evolution_pending_since!
  end

  def first_incoming_in_pending_cycle?
    return false unless conversation.pending?
    return false unless evolution_pending_reopen?

    pending_since = conversation.additional_attributes&.[]('evolution_pending_since')
    scope = conversation.messages.incoming.where(created_at: ..created_at)
    scope = scope.where(created_at: Time.zone.parse(pending_since)..) if pending_since.present?
    scope.count <= 1
  end

  def stamp_evolution_pending_cycle!
    return unless evolution_pending_reopen?

    attrs = (conversation.additional_attributes || {}).stringify_keys
    attrs['evolution_pending_since'] = Time.current.utc.iso8601(3)
    # rubocop:disable Rails/SkipsModelValidations -- runtime metadata only
    conversation.update_columns(additional_attributes: attrs)
    # rubocop:enable Rails/SkipsModelValidations
  end

  def clear_evolution_pending_since!
    return if conversation.additional_attributes.blank?
    return if conversation.additional_attributes['evolution_pending_since'].blank?

    attrs = conversation.additional_attributes.stringify_keys.except('evolution_pending_since')
    # rubocop:disable Rails/SkipsModelValidations -- runtime metadata only
    conversation.update_columns(additional_attributes: attrs)
    # rubocop:enable Rails/SkipsModelValidations
  end

  def evolution_pending_reopen?
    channel = conversation.inbox.channel
    return false unless channel.is_a?(Channel::Whatsapp) && channel.provider == 'evolution'

    ActiveModel::Type::Boolean.new.cast((channel.provider_config || {})['conversation_pending'])
  end
end
