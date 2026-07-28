# frozen_string_literal: true

# Clones ActiveStorage blobs for message forward (pseudo-forward).
# New blobs avoid sharing storage with the source message (retention purge safe).
class Custom::Messages::AttachmentCloneService
  FORWARDABLE_FILE_TYPES = %w[image audio video file].freeze

  pattr_initialize [:account!, :attachment_ids!]

  def perform
    ids = Array.wrap(attachment_ids).map(&:to_i).uniq
    return [] if ids.blank?

    sources = Attachment.where(account_id: account.id, id: ids, file_type: FORWARDABLE_FILE_TYPES)
                        .includes(file_attachment: :blob)
    by_id = sources.index_by(&:id)

    ids.filter_map { |id| clone_attachment(by_id[id]) }
  end

  private

  def clone_attachment(attachment)
    return if attachment.blank?
    return unless attachment.file.attached?

    blob = attachment.file.blob
    blob.open do |file|
      ActiveStorage::Blob.create_and_upload!(
        io: file,
        filename: blob.filename,
        content_type: blob.content_type
      )
    end
  end
end
