# frozen_string_literal: true

module Custom::Call
  def recording_url
    return super if recording.attached?

    meta&.dig('record_url') if wavoip?
  end

  def sync_conversation_call_attributes!
    conversation.update!(
      additional_attributes: (conversation.additional_attributes || {}).merge(
        'call_status' => display_status,
        'call_direction' => direction_label
      )
    )
  end
end
