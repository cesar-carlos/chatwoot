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
    # Do not re-raise — status is already failed; Sidekiq retries would only no-op.
  end

  private

  def source_inbox
    @source_inbox ||= migration.source_inbox
  end

  def target_inbox
    @target_inbox ||= migration.target_inbox
  end

  def contact_inbox_resolver
    @contact_inbox_resolver ||= Custom::Inboxes::HistoryMigration::ContactInboxResolver.new(
      source_inbox: source_inbox,
      target_inbox: target_inbox
    )
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
      target_contact_inbox = contact_inbox_resolver.resolve(contact_inbox)
      if target_contact_inbox
        # Process newest-first so the most recent conversation becomes the
        # surviving container in the target; older ones are merged into it.
        contact_inbox.conversations.order(id: :desc).find_each do |conversation|
          migrate_conversation!(conversation, target_contact_inbox)
        end
      end
    end

    # Increment outside the lock — a non-local `return` inside with_lock rolls
    # back the transaction and would undo stats updates.
    if target_contact_inbox.nil?
      increment_failed_for_contact_inbox!(contact_inbox)
    else
      cleanup_orphaned_source_contact_inbox!(contact_inbox)
    end
  rescue StandardError => e
    Rails.logger.error(
      "[InboxHistoryMigration] ##{migration.id} contact_inbox=#{contact_inbox.id} failed: #{e.class} #{e.message}"
    )
    increment_failed_for_contact_inbox!(contact_inbox)
  end

  def increment_failed_for_contact_inbox!(contact_inbox)
    count = contact_inbox.conversations.count
    return if count.zero?

    migration.increment_stat!(:failed, by: count)
  end

  def cleanup_orphaned_source_contact_inbox!(contact_inbox)
    # Use delete (not destroy!) — ContactInbox has `dependent: :destroy_async` on
    # conversations; a race that attaches a new thread between the empty check and
    # destroy would enqueue wiping that conversation.
    contact_inbox.with_lock do
      next if contact_inbox.conversations.exists?

      contact_inbox.delete
    end
  rescue StandardError => e
    Rails.logger.warn(
      "[InboxHistoryMigration] ##{migration.id} orphan contact_inbox=#{contact_inbox.id} cleanup failed: #{e.class} #{e.message}"
    )
  end

  def migrate_conversation!(conversation, target_contact_inbox)
    if already_on_target?(conversation, target_contact_inbox)
      migration.increment_stat!(:skipped)
      return
    end

    existing = target_contact_inbox.conversations.order(created_at: :desc).first
    if existing.present? && existing.id != conversation.id
      merge_conversation!(conversation, existing)
    else
      remount_conversation!(conversation, target_contact_inbox)
    end
  end

  def already_on_target?(conversation, target_contact_inbox)
    conversation.inbox_id == target_inbox.id &&
      conversation.contact_inbox_id == target_contact_inbox.id
  end

  def merge_conversation!(conversation, existing)
    Custom::Inboxes::HistoryMigration::ConversationMerger.new(
      source_conversation: conversation,
      target_conversation: existing,
      target_inbox: target_inbox
    ).perform
    migration.increment_stat!(:merged)
  end

  def remount_conversation!(conversation, target_contact_inbox)
    Custom::Inboxes::HistoryMigration::Remounter.new(
      conversation: conversation,
      target_inbox: target_inbox,
      target_contact_inbox: target_contact_inbox,
      source_inbox: source_inbox
    ).perform
    migration.increment_stat!(:moved)
  end

  def heartbeat_if_needed!
    @processed += 1
    return unless (@processed % HEARTBEAT_EVERY).zero?

    migration.touch_heartbeat!
  end
end
