# frozen_string_literal: true

module Custom::Whatsapp::IncomingMessageBaseService
  EVOLUTION_PUSH_NAME_KEY = Custom::Whatsapp::Evolution::ContactEnrichmentService::EVOLUTION_PUSH_NAME_KEY
  STATUS_PROGRESSION = %w[sent delivered read].freeze

  def process_statuses
    return super unless evolution_channel?

    status = @processed_params[:statuses].first
    unless find_message_by_source_id(status[:id])
      Custom::Whatsapp::Evolution::DeferredStatusJob.set(
        wait: Custom::Whatsapp::Evolution::DeferredStatusJob::DEFER_WAIT
      ).perform_later(
        inbox.id,
        status.deep_stringify_keys,
        1
      )
      Rails.logger.info(
        "[EVOLUTION] status update deferred source_id=#{status[:id]} status=#{status[:status]} attempt=1/" \
        "#{Custom::Whatsapp::Evolution::DeferredStatusJob::MAX_ATTEMPTS}"
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

  def set_conversation
    super
  ensure
    # FORK: avoid leaking opened_by into the next Sidekiq job on this thread
    Current.conversation_opened_by = nil
  end

  def process_messages
    return super unless evolution_channel?

    begin
      super
    rescue StandardError
      release_evolution_inbound_dedup_lock!
      raise
    end
  end

  def lock_message_source_id!
    return super unless evolution_channel?

    source_id = messages_data&.first&.dig(:id)
    return false if source_id.blank?

    lock = Whatsapp::MessageDedupLock.new(source_id)
    if lock.acquire!
      @evolution_dedup_lock = lock
      @evolution_dedup_lock_acquired = true
      return true
    end

    raise MutexApplicationJob::LockAcquisitionError,
          "Evolution inbound dedup lock busy for source_id=#{source_id}"
  end

  def release_evolution_inbound_dedup_lock!
    return unless @evolution_dedup_lock_acquired

    @evolution_dedup_lock.release!
    @evolution_dedup_lock_acquired = false
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
