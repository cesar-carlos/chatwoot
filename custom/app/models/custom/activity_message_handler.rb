module Custom::ActivityMessageHandler
  def automation_status_change_activity_content
    if Current.executed_by.instance_of?(ConversationWorkflowRule)
      return I18n.t(
        'conversations.activity.workflow_rule.status_change',
        rule_name: Current.executed_by.name
      )
    end

    super
  end
end

ActivityMessageHandler.prepend_mod_with('ActivityMessageHandler')
