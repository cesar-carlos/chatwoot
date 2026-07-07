# frozen_string_literal: true

module Custom::Message
  extend ActiveSupport::Concern

  prepended do
    prepend Custom::Message::EvolutionConversationCycle
    prepend Custom::Message::EvolutionDeleteSync
    prepend Custom::Message::EvolutionGoDeleteSync
    prepend Custom::Message::EvolutionGoEditSync
    prepend Custom::Message::WorkflowRulesScheduler
    prepend Custom::Message::WavoipConversationCycle

    before_validation :reject_voice_only_outbound_public_message, on: :create

    after_create_commit :schedule_workflow_rules_on_incoming, if: :incoming?
    after_create_commit :schedule_workflow_rules_on_outgoing, if: :outgoing?
    after_update_commit :sync_evolution_delete_to_whatsapp
    after_update_commit :sync_evolution_go_delete_to_whatsapp
    after_update_commit :sync_evolution_go_edit_to_whatsapp
  end

  def send_reply
    return unless should_enqueue_send_reply?

    super
  end

  private

  def reject_voice_only_outbound_public_message
    return unless blocked_outbound_public_text?

    errors.add(:base, I18n.t('errors.wavoip.voice_only_inbox'))
  end

  def blocked_outbound_public_text?
    return false unless outgoing?
    return false if private?
    return false if activity?
    return false if voice_call?

    !Custom::Channels::OutboundText.allowed?(inbox&.channel)
  end

  def should_enqueue_send_reply?
    return false unless outgoing? || template?
    return false if private?
    return false if voice_call?
    return false unless Custom::Channels::OutboundText.allowed?(inbox.channel)

    channel_supported_for_send_reply?
  end

  def channel_supported_for_send_reply?
    channel_name = inbox.channel.class.to_s
    return true if channel_name == 'Channel::FacebookPage'

    SendReplyJob::CHANNEL_SERVICES[channel_name].present?
  end

  def history_import_message?
    ActiveModel::Type::Boolean.new.cast(content_attributes[:history_import])
  end
end
