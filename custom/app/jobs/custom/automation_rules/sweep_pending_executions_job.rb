class Custom::AutomationRules::SweepPendingExecutionsJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    rows = AutomationRulePendingExecution.sweepable.for_enabled_accounts.order(:due_at).limit(sweep_limit).to_a
    rows.each { |row| AutomationRules::ProcessPendingExecutionJob.perform_later(row) }
  end

  private

  def sweep_limit
    configured = InstallationConfig.find_by(name: 'AUTOMATION_PENDING_EXECUTIONS_SWEEP_LIMIT')&.value
    (configured || AutomationRules::TriggerPendingExecutionsJob::DEFAULT_SWEEP_LIMIT).to_i
  end
end
