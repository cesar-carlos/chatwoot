# frozen_string_literal: true

module Custom::Message
  extend ActiveSupport::Concern

  prepended do
    prepend Custom::Message::EvolutionConversationCycle
    prepend Custom::Message::EvolutionDeleteSync
    prepend Custom::Message::WorkflowRulesScheduler

    after_create_commit :schedule_workflow_rules_on_incoming, if: :incoming?
    after_create_commit :schedule_workflow_rules_on_outgoing, if: :outgoing?
    after_update_commit :sync_evolution_delete_to_whatsapp
  end

  private

  def history_import_message?
    ActiveModel::Type::Boolean.new.cast(content_attributes[:history_import])
  end
end
