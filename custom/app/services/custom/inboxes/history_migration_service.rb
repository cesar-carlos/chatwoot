# frozen_string_literal: true

class Custom::Inboxes::HistoryMigrationService
  HEARTBEAT_EVERY = 25

  pattr_initialize [:migration!]

  def perform
    @processed = 0
    migration.mark_running!
    migrate_contact_inboxes!
    migration.mark_completed!
  rescue StandardError => e
    Rails.logger.error("[InboxHistoryMigration] ##{migration.id} failed: #{e.class} #{e.message}")
    migration.mark_failed!(e.message)
    raise
  end

  private

  def source_inbox
    @source_inbox ||= migration.source_inbox
  end

  def target_inbox
    @target_inbox ||= migration.target_inbox
  end

  def migrate_contact_inboxes!
    total = source_inbox.contact_inboxes.count
    migration.update!(stats: migration.stats.merge('total' => total))

    source_inbox.contact_inboxes.find_each do |contact_inbox|
      migrate_contact_inbox!(contact_inbox)
      heartbeat_if_needed!
    end
  end

  def migrate_contact_inbox!(contact_inbox)
    contact_inbox.with_lock do
      target_contact_inbox = resolve_target_contact_inbox(contact_inbox)
      unless target_contact_inbox
        migration.increment_stat!(:failed)
        return
      end

      contact_inbox.conversations.find_each do |conversation|
        migrate_conversation!(conversation, target_contact_inbox)
      end
    end
  rescue StandardError => e
    Rails.logger.error(
      "[InboxHistoryMigration] ##{migration.id} contact_inbox=#{contact_inbox.id} failed: #{e.class} #{e.message}"
    )
    migration.increment_stat!(:failed)
  end

  def resolve_target_contact_inbox(contact_inbox)
    ContactInboxBuilder.new(
      contact: contact_inbox.contact,
      inbox: target_inbox,
      source_id: source_id_for_builder(contact_inbox)
    ).perform
  rescue ActionController::ParameterMissing
    fallback_contact_inbox(contact_inbox)
  end

  def source_id_for_builder(contact_inbox)
    # Prefer builder auto-generation from phone when possible.
    # Evolution group JIDs are only portable between Evolution / Evolution Go.
    return contact_inbox.source_id if portable_evolution_group?(contact_inbox)

    nil
  end

  def portable_evolution_group?(contact_inbox)
    return false unless Custom::Inboxes::HistoryMigration::CompatibilityGuard.evolution_family?(source_inbox)
    return false unless Custom::Inboxes::HistoryMigration::CompatibilityGuard.evolution_family?(target_inbox)

    evolution_group_source?(contact_inbox)
  end

  def evolution_group_source?(contact_inbox)
    Custom::Whatsapp::Evolution::GroupContactService.group_jid?(contact_inbox.source_id)
  rescue NameError
    contact_inbox.source_id.to_s.end_with?('@g.us')
  end

  def fallback_contact_inbox(contact_inbox)
    return nil unless portable_evolution_group?(contact_inbox)

    ContactInbox.find_or_create_by!(
      inbox: target_inbox,
      contact: contact_inbox.contact,
      source_id: contact_inbox.source_id
    )
  end

  def migrate_conversation!(conversation, target_contact_inbox)
    # Skip if this conversation already points at the target (idempotent re-run)
    if conversation.inbox_id == target_inbox.id && conversation.contact_inbox_id == target_contact_inbox.id
      migration.increment_stat!(:skipped)
      return
    end

    existing = Conversations::Resolver.new(
      inbox: target_inbox,
      contact_inbox: target_contact_inbox
    ).find

    if existing.present? && existing.id != conversation.id
      Custom::Inboxes::HistoryMigration::ConversationMerger.new(
        source_conversation: conversation,
        target_conversation: existing,
        target_inbox: target_inbox
      ).perform
      migration.increment_stat!(:merged)
    else
      Custom::Inboxes::HistoryMigration::Remounter.new(
        conversation: conversation,
        target_inbox: target_inbox,
        target_contact_inbox: target_contact_inbox,
        source_inbox: source_inbox
      ).perform
      migration.increment_stat!(:moved)
    end
  end

  def heartbeat_if_needed!
    @processed += 1
    return unless (@processed % HEARTBEAT_EVERY).zero?

    migration.touch_heartbeat!
  end
end
