# frozen_string_literal: true

class Custom::Inboxes::HistoryMigrationService
  class ExecutionStopped < StandardError; end

  pattr_initialize [:migration!]

  def perform
    migration.mark_running!
    migrate_contact_inboxes!
    ensure_running!
    migration.mark_completed!
  rescue ExecutionStopped => e
    Rails.logger.warn("[InboxHistoryMigration] ##{migration.id} stopped: #{e.message}")
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
      ensure_running!
      migration.touch_heartbeat!
      migrate_contact_inbox!(contact_inbox)
    end
  end

  def migrate_contact_inbox!(contact_inbox)
    target_contact_inbox = contact_inbox.with_lock do
      contact_inbox_resolver.resolve(contact_inbox)
    end

    if target_contact_inbox.nil?
      increment_failed_for_contact_inbox!(contact_inbox)
      return
    end

    # Active Record ignores a scoped order in find_each. Passing order explicitly
    # guarantees that the newest source conversation becomes the target container.
    contact_inbox.conversations.find_each(order: :desc) do |conversation|
      migrate_conversation_safely!(conversation, target_contact_inbox)
    end
    cleanup_orphaned_source_contact_inbox!(contact_inbox)
  rescue StandardError => e
    raise if e.is_a?(ExecutionStopped)

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

  def migrate_conversation_safely!(conversation, target_contact_inbox)
    conversation.with_lock do
      ensure_running!
      migrate_conversation!(conversation, target_contact_inbox)
    end
  rescue StandardError => e
    raise if e.is_a?(ExecutionStopped)

    Rails.logger.error(
      "[InboxHistoryMigration] ##{migration.id} conversation=#{conversation.id} failed: #{e.class} #{e.message}"
    )
    migration.increment_stat!(:failed)
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

  def ensure_running!
    return if migration.reload.status == 'running'

    raise ExecutionStopped, "migration status changed to #{migration.status}"
  end
end
