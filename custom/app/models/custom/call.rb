# frozen_string_literal: true

module Custom::Call
  def recording_url
    return super if recording.attached?

    meta&.dig('record_url') if wavoip?
  end
end
