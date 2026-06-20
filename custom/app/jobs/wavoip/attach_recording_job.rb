# frozen_string_literal: true

class Wavoip::AttachRecordingJob < ApplicationJob
  queue_as :low

  def perform(call_id, record_url)
    call = Call.find_by(id: call_id)
    return if call.blank? || record_url.blank?

    Wavoip::Calls::RecordingAttachmentService.new(call: call, record_url: record_url).perform
  end
end
