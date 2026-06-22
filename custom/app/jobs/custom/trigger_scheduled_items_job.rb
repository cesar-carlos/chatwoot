# frozen_string_literal: true

module Custom::TriggerScheduledItemsJob
  def perform
    super
    Custom::Whatsapp::Evolution::LostMessagesReconciliationJob.perform_later
  end
end

TriggerScheduledItemsJob.prepend_mod_with('TriggerScheduledItemsJob')
