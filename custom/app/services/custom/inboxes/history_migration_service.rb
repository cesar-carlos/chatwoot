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
    total = source_inbox.conversations.count
    migration.update!(stats: migration.stats.merge('total' => total))

    source_inbox.contact_inboxes.find_each do |contact_inbox|
      migrate_contact_inbox!(contact_inbox)
      heartbeat_if_needed!
    end
  end

  def migrate_contact_inbox!(contact_inbox)
    target_contact_inbox = nil
    contact_inbox.with_lock do
      target_contact_inbox = resolve_target_contact_inbox(contact_inbox)
      if target_contact_inbox
        contact_inbox.conversations.find_each do |conversation|
          migrate_conversation!(conversation, target_contact_inbox)
        end
      end
    end

    # Increment outside the lock — a non-local `return` inside with_lock rolls
    # back the transaction and would undo stats updates.
    increment_failed_for_contact_inbox!(contact_inbox) if target_contact_inbox.nil?
  rescue StandardError => e
    Rails.logger.error(
      "[InboxHistoryMigration] ##{migration.id} contact_inbox=#{contact_inbox.id} failed: #{e.class} #{e.message}"
    )
    increment_failed_for_contact_inbox!(contact_inbox)
  end

  def increment_failed_for_contact_inbox!(contact_inbox)
    # Stats are conversation-scoped (moved/merged/skipped/failed).
    count = contact_inbox.conversations.count
    migration.increment_stat!(:failed, by: [count, 1].max)
  end

  def resolve_target_contact_inbox(contact_inbox)
    # Idempotent: reuse an existing session for this contact on the target inbox
    # (covers WA→API UUID re-runs and peers already opened on the destination).
    existing_for_contact = ContactInbox.find_by(
      inbox_id: target_inbox.id,
      contact_id: contact_inbox.contact_id
    )
    return existing_for_contact if existing_for_contact

    source_id = resolved_source_id(contact_inbox)
    return create_api_contact_inbox!(contact_inbox) if source_id.blank? && target_inbox.api?
    return fallback_contact_inbox(contact_inbox) if source_id.blank?

    create_contact_inbox_safely!(contact_inbox.contact, source_id)
  end

  # Prefer an explicit portable id; otherwise derive a target-native id.
  def resolved_source_id(contact_inbox)
    explicit = source_id_for_builder(contact_inbox)
    return explicit if explicit.present?

    derived_source_id(contact_inbox.contact)
  end

  def derived_source_id(contact)
    return nil if contact.phone_number.blank?

    if target_inbox.whatsapp?
      contact.phone_number.delete('+').to_s
    elsif target_inbox.twilio_whatsapp?
      "whatsapp:#{contact.phone_number}"
    elsif target_inbox.twilio? || target_inbox.sms?
      contact.phone_number
    elsif target_inbox.email?
      contact.email
    end
  end

  def source_id_for_builder(contact_inbox)
    # Evolution group JIDs are only portable between Evolution / Evolution Go.
    return contact_inbox.source_id if portable_evolution_group?(contact_inbox)
    # API/Webhook sessions are opaque UUIDs — preserve only for API→API.
    return contact_inbox.source_id if source_inbox.api? && target_inbox.api?

    # Same-family WhatsApp-like: preserve or convert format (Twilio ↔ Cloud).
    return portable_whatsapp_source_id(contact_inbox) if whatsapp_like_pair?

    # Cross-family (API↔WhatsApp): never copy UUID/JID across channel types.
    # Caller derives phone for WA or generates UUID for API.
    nil
  end

  def whatsapp_like_pair?
    guard = Custom::Inboxes::HistoryMigration::CompatibilityGuard
    guard.whatsapp_like?(source_inbox) && guard.whatsapp_like?(target_inbox)
  end

  def portable_whatsapp_source_id(contact_inbox)
    sid = contact_inbox.source_id.to_s
    return nil if sid.blank?

    # Groups only move within Evolution family (already handled above); otherwise fail closed.
    if evolution_group_source?(contact_inbox)
      return nil unless portable_evolution_group?(contact_inbox)

      return sid
    end

    if source_inbox.whatsapp? && target_inbox.whatsapp?
      return sid if sid.match?(RegexHelper::WHATSAPP_CHANNEL_REGEX)

      return nil
    end

    if source_inbox.twilio_whatsapp? && target_inbox.twilio_whatsapp?
      return sid if sid.match?(RegexHelper::TWILIO_CHANNEL_WHATSAPP_REGEX)

      return nil
    end

    convert_whatsapp_source_id(sid)
  end

  def convert_whatsapp_source_id(sid)
    if target_inbox.whatsapp?
      digits = sid.sub(/\Awhatsapp:\+?/, '')
      return digits if digits.match?(RegexHelper::WHATSAPP_CHANNEL_REGEX)

      nil
    elsif target_inbox.twilio_whatsapp?
      return sid if sid.match?(RegexHelper::TWILIO_CHANNEL_WHATSAPP_REGEX)
      return "whatsapp:+#{sid}" if sid.match?(/\A\d{1,15}\z/)
      return "whatsapp:#{sid}" if sid.match?(RegexHelper::WHATSAPP_BSUID_REGEX)

      nil
    end
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

    create_contact_inbox_safely!(contact_inbox.contact, contact_inbox.source_id)
  end

  def create_api_contact_inbox!(contact_inbox)
    existing = ContactInbox.find_by(inbox_id: target_inbox.id, contact_id: contact_inbox.contact_id)
    return existing if existing

    ContactInbox.create!(
      inbox: target_inbox,
      contact: contact_inbox.contact,
      source_id: SecureRandom.uuid
    )
  rescue ActiveRecord::RecordNotUnique
    ContactInbox.find_by(inbox_id: target_inbox.id, contact_id: contact_inbox.contact_id)
  end

  # Create without ContactInboxBuilder — avoids its "steal" rewrite on collision.
  def create_contact_inbox_safely!(contact, source_id)
    existing = ContactInbox.find_by(inbox_id: target_inbox.id, source_id: source_id)
    if existing
      return existing if existing.contact_id == contact.id

      return nil
    end

    ContactInbox.create!(inbox: target_inbox, contact: contact, source_id: source_id)
  rescue ActiveRecord::RecordNotUnique
    existing = ContactInbox.find_by(inbox_id: target_inbox.id, source_id: source_id)
    return existing if existing&.contact_id == contact.id

    nil
  rescue ActiveRecord::RecordInvalid
    nil
  end

  def migrate_conversation!(conversation, target_contact_inbox)
    # Skip if this conversation already points at the target (idempotent re-run)
    if conversation.inbox_id == target_inbox.id && conversation.contact_inbox_id == target_contact_inbox.id
      migration.increment_stat!(:skipped)
      return
    end

    # History migration always considers resolved threads on the destination
    # (unlike Conversations::Resolver when lock_to_single_conversation is off).
    existing = target_contact_inbox.conversations.order(created_at: :desc).first

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
