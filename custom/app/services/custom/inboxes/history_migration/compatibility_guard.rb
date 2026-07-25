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
    validate_compatible_channels!
    validate_not_already_in_progress!
  end

  def self.whatsapp_like?(inbox)
    return false if inbox.blank?

    inbox.whatsapp? || inbox.twilio_whatsapp?
  end

  def self.compatible?(source_inbox, target_inbox)
    return false if source_inbox.blank? || target_inbox.blank?

    (whatsapp_like?(source_inbox) && whatsapp_like?(target_inbox)) ||
      (source_inbox.api? && target_inbox.api?) ||
      (whatsapp_like?(source_inbox) && target_inbox.api?) ||
      (source_inbox.api? && whatsapp_like?(target_inbox))
  end

  def self.evolution_family?(inbox)
    return false unless inbox&.whatsapp?

    inbox.channel.provider.to_s.in?(%w[evolution evolution_go])
  end

  def self.expire_stale_for_inbox_ids!(ids)
    InboxHistoryMigration
      .where(status: %w[pending running])
      .for_inbox_ids(ids)
      .find_each(&:expire_if_stale!)
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

  def validate_compatible_channels!
    return if self.class.compatible?(source, target)

    raise Error.new(
      I18n.t('errors.inbox_history_migration.incompatible_channels'),
      code: 'incompatible_channels'
    )
  end

  def validate_not_already_in_progress!
    self.class.expire_stale_for_inbox_ids!([source.id, target.id])

    in_progress = InboxHistoryMigration
                  .blocking_progress
                  .for_inbox_ids([source.id, target.id])
                  .exists?
    return unless in_progress

    raise Error.new(
      I18n.t('errors.inbox_history_migration.already_running'),
      code: 'already_running'
    )
  end
end
