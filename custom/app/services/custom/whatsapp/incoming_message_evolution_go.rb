# frozen_string_literal: true

module Custom::Whatsapp::IncomingMessageEvolutionGo
  EVOLUTION_GO_REMOTE_JID_KEY = 'evolution_go_remote_jid'

  def process_statuses
    return super unless evolution_go_channel?

    statuses = Array.wrap(@processed_params[:statuses]).filter_map(&:with_indifferent_access)
    return if statuses.blank?

    statuses.each { |status| process_evolution_go_status(status) }
  end

  def process_evolution_go_status(status)
    return if status[:id].blank?

    unless find_message_by_source_id(status[:id])
      defer_evolution_go_status(status)
      return
    end

    update_whatsapp_identifiers_from_status(status)
    update_message_with_status(@message, status)
  rescue ArgumentError => e
    Rails.logger.error "Error while processing Evolution Go status update #{e.message}"
  end

  def defer_evolution_go_status(status)
    Custom::Whatsapp::Evolution::DeferredStatusJob.set(
      wait: Custom::Whatsapp::Evolution::DeferredStatusJob::DEFER_WAIT
    ).perform_later(
      inbox.id,
      status.deep_stringify_keys,
      1
    )
    Rails.logger.info(
      "[EVOLUTION_GO] status update deferred source_id=#{status[:id]} status=#{status[:status]} attempt=1/" \
      "#{Custom::Whatsapp::Evolution::DeferredStatusJob::MAX_ATTEMPTS}"
    )
  end

  def update_message_with_status(message, status)
    return super unless evolution_go_channel?

    new_status = status[:status].to_s
    return unless status_promotion?(message.status, new_status)

    super
  end

  def create_regular_message(message)
    super
    enqueue_pending_evolution_go_media_download if evolution_go_channel?
  end

  def download_attachment_file(attachment_payload)
    return download_evolution_go_media(attachment_payload) if evolution_go_channel? && attachment_payload[:_evolution_go_message].present?

    super
  end

  private

  def find_message_by_source_id(source_id)
    return super unless evolution_go_channel?

    return unless source_id

    @message = inbox.messages.find_by(source_id: source_id)
  end

  def message_content_attributes(message)
    attrs = super
    return attrs unless evolution_go_channel?

    remote_jid = message[:evolution_go_remote_jid].presence || message['evolution_go_remote_jid'].presence
    attrs[EVOLUTION_GO_REMOTE_JID_KEY] = remote_jid if remote_jid.present?
    attrs
  end

  def download_evolution_go_media(attachment_payload)
    @pending_evolution_go_media = attachment_payload
    nil
  end

  def enqueue_pending_evolution_go_media_download
    return if @pending_evolution_go_media.blank? || @message.blank? || @message.id.blank?

    Custom::Whatsapp::EvolutionGo::MediaDownloadJob.perform_later(
      inbox.channel.id,
      @message.id,
      @pending_evolution_go_media.deep_stringify_keys,
      message_type.to_s
    )
    @pending_evolution_go_media = nil
  end

  def evolution_go_channel?
    inbox.channel.is_a?(Channel::Whatsapp) && inbox.channel.provider == 'evolution_go'
  end

  def status_promotion?(current, new_status)
    return true if new_status == 'failed'
    return false unless Custom::Whatsapp::IncomingMessageBaseService::STATUS_PROGRESSION.include?(new_status)

    current_index = Custom::Whatsapp::IncomingMessageBaseService::STATUS_PROGRESSION.index(current.to_s) || -1
    new_index = Custom::Whatsapp::IncomingMessageBaseService::STATUS_PROGRESSION.index(new_status)
    new_index > current_index
  end
end

Whatsapp::IncomingMessageBaseService.prepend(Custom::Whatsapp::IncomingMessageEvolutionGo)
