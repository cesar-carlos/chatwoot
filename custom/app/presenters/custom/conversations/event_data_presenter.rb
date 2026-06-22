# frozen_string_literal: true

module Custom::Conversations::EventDataPresenter
  def push_data
    super.merge(last_non_activity_message: last_non_activity_message_event_data)
  end

  private

  def last_non_activity_message_event_data
    messages.where(account_id: account_id).non_activity_messages.first&.push_event_data
  end
end

Conversations::EventDataPresenter.prepend_mod_with('Conversations::EventDataPresenter')
