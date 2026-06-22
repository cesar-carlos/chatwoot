# rubocop:disable Metrics/ModuleLength -- Evolution conversation reopen and delete sync hooks
module Custom::Message
  extend ActiveSupport::Concern

  prepended do
    after_create_commit :schedule_workflow_rules_on_incoming, if: :incoming?
    after_create_commit :schedule_workflow_rules_on_outgoing, if: :outgoing?
    after_update_commit :sync_evolution_delete_to_whatsapp
  end

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
    return activate_from_snoozed! if conversation.snoozed?

    open_evolution_pending_cycle_if_needed
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

  def sync_evolution_delete_to_whatsapp
    return unless evolution_message_marked_deleted?

    Custom::Whatsapp::Evolution::DeleteSyncService.new(message: self).perform
  end

  def evolution_message_marked_deleted?
    channel = evolution_whatsapp_channel
    return false unless channel
    return false unless evolution_sync_delete_enabled?(channel)
    return false unless newly_marked_deleted?

    true
  end

  def evolution_whatsapp_channel
    channel = conversation&.inbox&.channel
    return unless channel.is_a?(Channel::Whatsapp) && channel.provider == 'evolution'

    channel
  end

  def evolution_sync_delete_enabled?(channel)
    ActiveModel::Type::Boolean.new.cast((channel.provider_config || {})['sync_delete_to_whatsapp'])
  end

  def newly_marked_deleted?
    return false if source_id.blank?
    return false unless ActiveModel::Type::Boolean.new.cast(content_attributes[:deleted])
    return false if ActiveModel::Type::Boolean.new.cast(content_attributes[:deleted_via_evolution_webhook])

    before = (content_attributes_before_last_save || {}).with_indifferent_access
    !ActiveModel::Type::Boolean.new.cast(before[:deleted])
  end

  def schedule_workflow_rules_on_incoming
    return if history_import_message?

    schedule_workflow_rules_for(ConversationWorkflowRule.method(:schedulable_on_incoming?))
  end

  def schedule_workflow_rules_on_outgoing
    return if history_import_message?

    account = conversation&.account
    return if account.blank?

    account.conversation_workflow_rules.active.customer_no_reply.find_each do |rule|
      next unless account.feature_enabled?('auto_resolve_conversations')
      next if rule.inbox_ids.present? && Array(rule.inbox_ids).exclude?(conversation.inbox_id)

      Custom::ConversationWorkflow::ScheduleOnMessageScheduler.new(
        rule: rule,
        conversation: conversation
      ).perform_for_outgoing_message(self)
    end
  end

  def schedule_workflow_rules_for(trigger_check)
    account = conversation&.account
    return if account.blank?

    account.conversation_workflow_rules.active.find_each do |rule|
      next unless workflow_rule_applies?(rule, account, trigger_check)

      Custom::ConversationWorkflow::ScheduleOnMessageScheduler.new(
        rule: rule,
        conversation: conversation
      ).perform
    end
  end

  def workflow_rule_applies?(rule, account, trigger_check)
    trigger_check.call(rule.trigger_type) &&
      feature_enabled_for_trigger?(account, rule) &&
      rule_applies_to_inbox?(rule) &&
      !first_response_already_sent?(rule)
  end

  def rule_applies_to_inbox?(rule)
    rule.inbox_ids.blank? || Array(rule.inbox_ids).include?(conversation.inbox_id)
  end

  def first_response_already_sent?(rule)
    rule.first_response_overdue? && conversation.first_reply_created_at.present?
  end

  def feature_enabled_for_trigger?(account, rule)
    flag = Custom::ConversationWorkflow::AccountProcessor::FEATURE_FLAG_BY_TRIGGER[rule.trigger_type]
    flag.blank? || account.feature_enabled?(flag)
  end

  def history_import_message?
    ActiveModel::Type::Boolean.new.cast(content_attributes[:history_import])
  end
end
# rubocop:enable Metrics/ModuleLength
