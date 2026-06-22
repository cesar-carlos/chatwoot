# frozen_string_literal: true

module Custom::Whatsapp::IncomingMessageServiceHelpers
  def conversation_params
    params = super
    return params unless evolution_conversation_pending?

    params.merge(
      status: :pending,
      additional_attributes: pending_cycle_attributes(params[:additional_attributes])
    )
  end

  def pending_cycle_attributes(existing_attrs)
    (existing_attrs || {}).stringify_keys.merge(
      'evolution_pending_since' => Time.current.utc.iso8601(3)
    )
  end

  def download_attachment_file(attachment_payload)
    return download_evolution_media(attachment_payload) if evolution_channel? && attachment_payload[:_evolution_message].present?

    super
  end

  private

  def find_message_by_source_id(source_id)
    return super unless evolution_channel?

    return unless source_id

    @message = inbox.messages.find_by(source_id: source_id)
  end

  def evolution_channel?
    inbox.channel.is_a?(Channel::Whatsapp) && inbox.channel.provider == 'evolution'
  end

  def evolution_conversation_pending?
    evolution_channel? && ActiveModel::Type::Boolean.new.cast(
      (inbox.channel.provider_config || {})['conversation_pending']
    )
  end

  def message_content_attributes(message)
    attrs = super
    return attrs unless evolution_channel?

    remote_jid = message[:evolution_remote_jid].presence || message['evolution_remote_jid'].presence
    attrs[:evolution_remote_jid] = remote_jid if remote_jid.present?
    attrs
  end

  def download_evolution_media(attachment_payload)
    @pending_evolution_media = attachment_payload
    nil
  end

  def enqueue_pending_evolution_media_download
    return if @pending_evolution_media.blank? || @message.blank? || @message.id.blank?

    Custom::Whatsapp::Evolution::MediaDownloadJob.perform_later(
      inbox.channel.id,
      @message.id,
      @pending_evolution_media.deep_stringify_keys,
      message_type.to_s
    )
    @pending_evolution_media = nil
  end
end

Whatsapp::IncomingMessageServiceHelpers.prepend_mod_with('Whatsapp::IncomingMessageServiceHelpers')
