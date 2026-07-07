# frozen_string_literal: true

class Custom::Avatar::AvatarFromBase64Job < ApplicationJob
  queue_as :purgable

  ALLOWED_CONTENT_TYPES = Avatarable::ALLOWED_AVATAR_CONTENT_TYPES

  def perform(avatarable, base64_data, content_type: 'image/jpeg')
    return unless avatarable.respond_to?(:avatar)
    return if base64_data.blank? || avatarable.avatar.attached?

    decoded = Base64.decode64(strip_data_uri(base64_data))
    return if decoded.blank?

    tempfile = Tempfile.new(['avatar', content_type_extension(content_type)])
    tempfile.binmode
    tempfile.write(decoded)
    tempfile.rewind

    avatarable.avatar.attach(
      io: tempfile,
      filename: "avatar#{content_type_extension(content_type)}",
      content_type: content_type
    )
  ensure
    tempfile&.close
    tempfile&.unlink
  end

  private

  def strip_data_uri(data)
    value = data.to_s.gsub(/\s+/, '')
    return value unless value.include?(',')

    value.split(',', 2).last
  end

  def content_type_extension(content_type)
    case content_type.to_s
    when 'image/png' then '.png'
    when 'image/webp' then '.webp'
    when 'image/gif' then '.gif'
    else '.jpg'
    end
  end
end
