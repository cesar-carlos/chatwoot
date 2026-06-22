module Custom::Internal::TriggerDailyScheduledItemsJob
  def perform
    super

    Custom::Retention::SchedulerJob.perform_later if Custom::Retention::Policy.enabled?
  end
end

Internal::TriggerDailyScheduledItemsJob.prepend_mod_with('Internal::TriggerDailyScheduledItemsJob')
