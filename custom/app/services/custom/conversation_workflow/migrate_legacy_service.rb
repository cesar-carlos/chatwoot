class Custom::ConversationWorkflow::MigrateLegacyService
  def initialize(account)
    @account = account
  end

  def perform
    @account.with_lock do
      return if @account.workflow_rules_migrated?
      return if @account.auto_resolve_after.blank?

      @account.conversation_workflow_rules.create!(
        name: 'Auto-resolve (migrated)',
        trigger_type: :conversation_inactivity,
        duration_minutes: @account.auto_resolve_after,
        message: @account.auto_resolve_message,
        ignore_waiting: @account.auto_resolve_ignore_waiting == true,
        resolve_on_match: true,
        actions: build_label_action(@account.auto_resolve_label),
        position: 0
      )

      settings = @account.settings.merge('workflow_rules_migrated_at' => Time.current.iso8601)
      @account.update!(settings: settings)
    end
  end

  private

  def build_label_action(label)
    return [] if label.blank?

    [{ 'action_name' => 'add_label', 'action_params' => [label] }]
  end
end
