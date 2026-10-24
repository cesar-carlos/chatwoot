# frozen_string_literal: true

# Explicit one-shot. Not scheduled. Pass an account id to limit the scan.
class Custom::Conversations::OpenedByBackfillJob < ApplicationJob
  queue_as :low

  def perform(account_id = nil)
    Custom::Conversations::OpenedByBackfill.perform!(account_id: account_id)
  end
end
