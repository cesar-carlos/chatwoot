class Custom::Retention::RecordPurgeEventService
  # rubocop:disable Metrics/ParameterLists -- explicit audit fields keep call sites readable
  def initialize(account:, attachment:, run_id:, status:, error_message: nil, byte_size: nil, blob_key: nil)
    @account = account
    @attachment = attachment
    @run_id = run_id
    @status = status
    @error_message = error_message
    @byte_size = byte_size
    @blob_key = blob_key
  end
  # rubocop:enable Metrics/ParameterLists

  def perform
    AttachmentRetentionEvent.create!(
      account: @account,
      attachment_id: @attachment.id,
      message_id: @attachment.message_id,
      blob_key: resolved_blob_key,
      byte_size: resolved_byte_size,
      attachment_created_at: @attachment.created_at,
      status: @status,
      error_message: @error_message,
      run_id: @run_id
    )
  end

  private

  def resolved_blob_key
    @blob_key || @attachment.file.blob&.key
  end

  def resolved_byte_size
    @byte_size || @attachment.file.blob&.byte_size.to_i
  end
end
