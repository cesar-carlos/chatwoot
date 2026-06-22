# frozen_string_literal: true

module Custom::Whatsapp::IncomingMessageBaseService
  EVOLUTION_PUSH_NAME_KEY = Custom::Whatsapp::Evolution::ContactEnrichmentService::EVOLUTION_PUSH_NAME_KEY
  STATUS_PROGRESSION = %w[sent delivered read].freeze

  def process_statuses
    return super unless evolution_channel?

    status = @processed_params[:statuses].first
    unless find_message_by_source_id(status[:id])
      Custom::Whatsapp::Evolution::DeferredStatusJob.set(wait: 5.seconds).perform_later(
        inbox.id,
        status.deep_stringify_keys
      )
      Rails.logger.info(
        "[EVOLUTION] status update deferred source_id=#{status[:id]} status=#{status[:status]}"
      )
      return
    end

    super
  end

  def update_message_with_status(message, status)
    return super unless evolution_channel?

    new_status = status[:status].to_s
    return unless status_promotion?(message.status, new_status)

    super
  end

  def update_contact_with_profile_name(contact_params)
    return super unless evolution_channel?

    profile_name = contact_params.dig(:profile, :name).to_s.strip
    return if profile_name.blank?
    return if @contact.name == profile_name
    return unless evolution_name_updatable?

    additional = @contact.additional_attributes.stringify_keys.merge(EVOLUTION_PUSH_NAME_KEY => profile_name)
    @contact.update!(name: profile_name, additional_attributes: additional)
  end

  def create_regular_message(message)
    super
    enqueue_pending_evolution_media_download if evolution_channel?
  end

  private

  def evolution_name_updatable?
    return true if @contact.name.blank?
    return true if contact_name_matches_phone_number?

    @contact.name == @contact.additional_attributes[EVOLUTION_PUSH_NAME_KEY]
  end

  def status_promotion?(current, new_status)
    return true if new_status == 'failed'
    return false unless STATUS_PROGRESSION.include?(new_status)

    current_index = STATUS_PROGRESSION.index(current.to_s) || -1
    new_index = STATUS_PROGRESSION.index(new_status)
    new_index > current_index
  end
end

Whatsapp::IncomingMessageBaseService.prepend_mod_with('Whatsapp::IncomingMessageBaseService')
