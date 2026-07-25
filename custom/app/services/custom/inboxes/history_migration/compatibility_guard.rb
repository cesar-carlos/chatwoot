# frozen_string_literal: true

class Custom::Inboxes::HistoryMigration::CompatibilityGuard
  class Error < StandardError
    attr_reader :code

    def initialize(message, code:)
      super(message)
      @code = code
    end
  end

  pattr_initialize [:source!, :target!]

  def validate!
    validate_same_account!
    validate_different_inboxes!
    validate_whatsapp_like!
    validate_not_already_running!
  end

  def self.whatsapp_like?(inbox)
    return false if inbox.blank?

    inbox.whatsapp? || inbox.twilio_whatsapp?
  end

  def self.evolution_family?(inbox)
    return false unless inbox&.whatsapp?

    inbox.channel.provider.to_s.in?(%w[evolution evolution_go])
  end

  private

  def validate_same_account!
    return if source.account_id == target.account_id

    raise Error.new(
      I18n.t('errors.inbox_history_migration.different_accounts'),
      code: 'different_accounts'
    )
  end

  def validate_different_inboxes!
    return if source.id != target.id

    raise Error.new(
      I18n.t('errors.inbox_history_migration.same_inbox'),
      code: 'same_inbox'
    )
  end

  def validate_whatsapp_like!
    return if self.class.whatsapp_like?(source) && self.class.whatsapp_like?(target)

    raise Error.new(
      I18n.t('errors.inbox_history_migration.incompatible_channels'),
      code: 'incompatible_channels'
    )
  end

  def validate_not_already_running!
    mark_stale_migrations_failed!

    running = InboxHistoryMigration
              .actively_running
              .where(
                'source_inbox_id IN (:ids) OR target_inbox_id IN (:ids)',
                ids: [source.id, target.id]
              )
              .exists?
    return unless running

    raise Error.new(
      I18n.t('errors.inbox_history_migration.already_running'),
      code: 'already_running'
    )
  end

  def mark_stale_migrations_failed!
    InboxHistoryMigration
      .where(status: 'running')
      .where(
        'source_inbox_id IN (:ids) OR target_inbox_id IN (:ids)',
        ids: [source.id, target.id]
      )
      .find_each do |migration|
        next unless migration.stale_running?

        migration.mark_failed!('Stale migration: heartbeat timed out')
      end
  end
end
