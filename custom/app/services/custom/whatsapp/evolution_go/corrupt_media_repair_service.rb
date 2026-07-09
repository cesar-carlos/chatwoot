# frozen_string_literal: true

class Custom::Whatsapp::EvolutionGo::CorruptMediaRepairService
  pattr_initialize [:attachment!]

  def perform
    blob = attachment.file&.blob
    return { status: :skipped, reason: 'no_blob' } if blob.blank?

    bytes = blob.download
    return { status: :skipped, reason: 'not_corrupt_data_url' } unless Custom::Whatsapp::EvolutionGo::CorruptMediaRepair.corrupt_data_url_blob?(bytes)

    recovered = Custom::Whatsapp::EvolutionGo::CorruptMediaRepair.recover(bytes)
    return { status: :failed, reason: 'recover_failed' } if recovered.blank?

    content_type = recovered[:mime_type].presence || blob.content_type
    unless Custom::Whatsapp::EvolutionGo::CorruptMediaRepair.valid_for_content_type?(recovered[:bytes], content_type)
      return { status: :failed, reason: 'invalid_recovered_magic', content_type: content_type }
    end

    replace_blob!(blob, recovered[:bytes], content_type)
    { status: :repaired, attachment_id: attachment.id, byte_size: recovered[:bytes].bytesize, content_type: content_type }
  end

  private

  def replace_blob!(old_blob, bytes, content_type)
    filename = old_blob.filename.to_s
    io = StringIO.new(bytes)
    attachment.file.attach(
      io: io,
      filename: filename,
      content_type: content_type,
      identify: false
    )
    attachment.save!
    old_blob.purge_later
  end
end
