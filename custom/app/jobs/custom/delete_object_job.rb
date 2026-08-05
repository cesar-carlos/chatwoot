module Custom::DeleteObjectJob
  private

  def purge_heavy_associations(object)
    purge_conversation_workflow_rule_executions(object) if object.is_a?(Account)
    super
  end

  def purge_conversation_workflow_rule_executions(account)
    rule_ids = account.conversation_workflow_rules.select(:id)
    ConversationWorkflowRuleSkip.where(conversation_workflow_rule_id: rule_ids).in_batches.delete_all
    ConversationWorkflowRuleExecution.where(conversation_workflow_rule_id: rule_ids).in_batches.delete_all
  end
end
