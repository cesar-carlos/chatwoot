# frozen_string_literal: true

# rubocop:disable Metrics/ClassLength -- enrichment mirrors Evolution Go contact profile fetch
class Custom::Whatsapp::EvolutionGo::ContactEnrichmentService
  ENRICHMENT_COOLDOWN = 24.hours
  # When /user/avatar times out, avoid re-enqueueing on every inbound message.
  AVATAR_RETRY_COOLDOWN = 6.hours
  WHATSAPP_STATUS_KEY = 'whatsapp_status'
  EVOLUTION_GO_PUSH_NAME_KEY = 'evolution_go_push_name'
  EVOLUTION_GO_REMOTE_JID_KEY = 'evolution_go_remote_jid'
  EVOLUTION_GO_ENRICHED_AT_KEY = 'evolution_go_enriched_at'
  EVOLUTION_GO_AVATAR_ATTEMPTED_AT_KEY = 'evolution_go_avatar_attempted_at'

  def self.should_enqueue?(contact:, remote_jid: nil, push_name: nil, force: false)
    return true if ActiveModel::Type::Boolean.new.cast(force)

    additional = contact.additional_attributes.to_h.stringify_keys
    return true if remote_jid.to_s.present? && additional[EVOLUTION_GO_REMOTE_JID_KEY] != remote_jid.to_s
    return true if push_name_changed?(contact, push_name)
    # Missing avatar used to always enqueue; that saturated Sidekiq when Go hung on /user/avatar.
    return true if !contact.avatar.attached? && avatar_attempt_stale?(contact)

    enrichment_stale?(contact)
  end

  def self.enrichment_stale?(contact)
    enriched_at = contact.additional_attributes.to_h[EVOLUTION_GO_ENRICHED_AT_KEY]
    return true if enriched_at.blank?

    Time.zone.parse(enriched_at) <= ENRICHMENT_COOLDOWN.ago
  rescue ArgumentError
    true
  end

  def self.avatar_attempt_stale?(contact)
    attempted_at = contact.additional_attributes.to_h[EVOLUTION_GO_AVATAR_ATTEMPTED_AT_KEY]
    return true if attempted_at.blank?

    Time.zone.parse(attempted_at) <= AVATAR_RETRY_COOLDOWN.ago
  rescue ArgumentError
    true
  end

  def self.push_name_changed?(contact, push_name)
    value = push_name.to_s.strip
    return false if value.blank?

    additional = contact.additional_attributes.to_h.stringify_keys
    current_name = contact.name.to_s.strip
    previous_push_name = additional[EVOLUTION_GO_PUSH_NAME_KEY].to_s.strip
    value != current_name && value != previous_push_name
  end

  def initialize(channel:, contact:, **options)
    @channel = channel
    @contact = contact
    @remote_jid = options[:remote_jid].to_s.presence
    @push_name = options[:push_name].to_s.strip.presence
    @force = ActiveModel::Type::Boolean.new.cast(options[:force])
  end

  def perform
    persist_remote_jid!
    update_name_from_push_name!
    fetch_and_apply_profile!
    mark_enriched!
  end

  private

  attr_reader :channel, :contact, :force

  def api_client
    @api_client ||= Custom::Whatsapp::EvolutionGo::ApiClient.for_channel(channel)
  end

  def lookup_jid
    return @remote_jid if @remote_jid.to_s.include?('@')

    phone = contact.phone_number.to_s.gsub(/\D/, '')
    return if phone.blank?

    "#{phone}@s.whatsapp.net"
  end

  def lookup_number
    lookup_jid&.split('@')&.first || contact.phone_number.to_s.gsub(/\D/, '')
  end

  def persist_remote_jid!
    return if @remote_jid.blank?

    updates = {}
    updates[:identifier] = @remote_jid if @remote_jid.end_with?('@lid') && contact.identifier != @remote_jid

    additional = contact.additional_attributes.stringify_keys
    return if additional[EVOLUTION_GO_REMOTE_JID_KEY] == @remote_jid && updates.blank?

    additional[EVOLUTION_GO_REMOTE_JID_KEY] = @remote_jid
    updates[:additional_attributes] = additional
    contact.update!(updates)
  end

  def update_name_from_push_name!
    return if @push_name.blank?
    return if contact.name == @push_name
    return unless name_updatable?

    additional = contact.additional_attributes.stringify_keys.merge(EVOLUTION_GO_PUSH_NAME_KEY => @push_name)
    contact.update!(name: @push_name, additional_attributes: additional)
  end

  def name_updatable?
    return true if contact.name.blank?
    return true if contact_name_matches_phone?

    last_push = contact.additional_attributes[EVOLUTION_GO_PUSH_NAME_KEY]
    contact.name == last_push
  end

  def contact_name_matches_phone?
    phone_number = contact.phone_number.to_s
    return false if phone_number.blank?

    formatted_phone_number = TelephoneNumber.parse(phone_number).international_number
    contact.name == phone_number || contact.name == formatted_phone_number
  end

  def fetch_and_apply_profile!
    jid = lookup_jid
    number = lookup_number
    return true if jid.blank? && number.blank?

    unless whatsapp_user_exists?(number)
      mark_avatar_attempted! unless contact.avatar.attached?
      return false
    end

    applied = false
    applied = apply_user_info!(jid) if jid.present?
    fetch_and_apply_avatar!(number) || applied

  rescue StandardError => e
    Rails.logger.warn("[EVOLUTION_GO] contact enrichment failed for contact #{contact.id}: #{e.message}")
    # /user/info can also hang; back off avatar retries so inbound traffic does not re-flood :low.
    mark_avatar_attempted! unless contact.avatar.attached?
    false
  end

  def apply_user_info!(jid)
    response = api_client.user_info(numbers: [jid])
    return false unless response.success?

    profile = extract_user_profile(response.parsed_response, jid)
    return false if profile.blank?

    apply_profile(profile, jid)
    true
  end

  def extract_user_profile(parsed, jid)
    data = parsed.is_a?(Hash) ? (parsed['data'] || parsed) : {}
    users = data['Users'] || data['users'] || {}
    users[jid] || users[jid.to_s] || users.values.first
  end

  def apply_profile(profile, jid) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    return if profile.blank?

    updates = {}
    additional = contact.additional_attributes.stringify_keys
    name = profile['VerifiedName'].to_s.strip.presence
    if name.present? && name_updatable? && contact.name != name
      updates[:name] = name
      additional[EVOLUTION_GO_PUSH_NAME_KEY] = name
    end

    status = profile['Status'].to_s.presence
    if status.present?
      custom = contact.custom_attributes.stringify_keys
      custom[WHATSAPP_STATUS_KEY] = status
      updates[:custom_attributes] = custom
    end

    lid = profile['LID'].to_s.presence
    updates[:identifier] = lid if lid.present? && lid.end_with?('@lid') && contact.identifier != lid

    additional[EVOLUTION_GO_REMOTE_JID_KEY] ||= jid
    updates[:additional_attributes] = additional if additional != contact.additional_attributes.stringify_keys
    contact.update!(updates) if updates.present?
  end

  def fetch_and_apply_avatar!(number)
    return false if number.blank?
    return false if contact.avatar.attached? && !force

    # preview: true returns a smaller payload and is more reliable for bulk refresh
    response = api_client.user_avatar(number: number, preview: true)
    unless response.success?
      Rails.logger.warn(
        "[EVOLUTION_GO] user/avatar failed for contact #{contact.id}: HTTP #{response.code}"
      )
      mark_avatar_attempted!
      return false
    end

    attach_avatar_from_response!(response.parsed_response)
  rescue Custom::Whatsapp::EvolutionGo::ApiError, *Custom::Whatsapp::EvolutionGo::ApiClient::NETWORK_ERRORS => e
    Rails.logger.warn("[EVOLUTION_GO] user/avatar error for contact #{contact.id}: #{e.message}")
    mark_avatar_attempted!
    false
  end

  def attach_avatar_from_response!(parsed)
    url = avatar_url_from_response(parsed)
    if url.present?
      prepare_avatar_resync! if force
      clear_avatar_attempt!
      ::Avatar::AvatarFromUrlJob.perform_later(contact, url)
      return true
    end

    base64 = avatar_base64_from_response(parsed)
    if base64.present?
      attached = attach_avatar_from_base64!(base64)
      if attached
        clear_avatar_attempt!
      else
        mark_avatar_attempted!
      end
      return attached
    end

    Rails.logger.info("[EVOLUTION_GO] user/avatar returned no URL/base64 for contact #{contact.id}")
    mark_avatar_attempted!
    false
  end

  def mark_avatar_attempted!
    additional = contact.additional_attributes.stringify_keys.merge(
      EVOLUTION_GO_AVATAR_ATTEMPTED_AT_KEY => Time.current.utc.iso8601(3)
    )
    contact.update!(additional_attributes: additional)
  end

  def clear_avatar_attempt!
    additional = contact.additional_attributes.stringify_keys
    return unless additional.key?(EVOLUTION_GO_AVATAR_ATTEMPTED_AT_KEY)

    additional.delete(EVOLUTION_GO_AVATAR_ATTEMPTED_AT_KEY)
    contact.update!(additional_attributes: additional)
  end

  def avatar_url_from_response(parsed)
    data = nested_response_data(parsed)
    [
      data['URL'],
      data['url'],
      data['ProfilePictureUrl'],
      data['profilePictureUrl'],
      parsed.is_a?(Hash) ? parsed['avatar_url'] : nil
    ].filter_map { |value| value.to_s.strip.presence }.find { |value| value.start_with?('http') }
  end

  def avatar_base64_from_response(parsed)
    data = nested_response_data(parsed)
    [
      data['avatar'],
      data['Avatar'],
      data['base64'],
      data['Base64'],
      parsed.is_a?(Hash) ? parsed['avatar'] : nil
    ].filter_map { |value| value.to_s.strip.presence }.first
  end

  def nested_response_data(parsed)
    return {} unless parsed.is_a?(Hash)

    data = parsed['data'] || parsed
    data.is_a?(Hash) ? data.with_indifferent_access : {}.with_indifferent_access
  end

  def attach_avatar_from_base64!(base64)
    bytes = Custom::Whatsapp::Evolution::MediaDecoder.decode!(base64)
    return false if bytes.blank?

    content_type = avatar_content_type_for(base64, bytes)
    return false unless Avatarable::ALLOWED_AVATAR_CONTENT_TYPES.include?(content_type)

    prepare_avatar_resync! if force || contact.avatar.attached?
    contact.avatar.attach(
      io: StringIO.new(bytes),
      filename: "evolution-go-avatar-#{contact.id}.#{avatar_extension_for(content_type)}",
      content_type: content_type
    )
    true
  rescue ArgumentError => e
    Rails.logger.warn("[EVOLUTION_GO] avatar base64 rejected for contact #{contact.id}: #{e.message}")
    false
  end

  def avatar_content_type_for(base64, bytes)
    Custom::Whatsapp::Evolution::MediaDecoder.mime_type_from_data_url(base64) ||
      detect_image_content_type(bytes)
  end

  def avatar_extension_for(content_type)
    extension = content_type.to_s.split('/').last
    extension == 'jpeg' ? 'jpg' : extension
  end

  def detect_image_content_type(bytes)
    return 'image/png' if bytes.start_with?("\x89PNG".b)
    return 'image/jpeg' if bytes.start_with?("\xFF\xD8\xFF".b)
    return 'image/gif' if bytes.start_with?('GIF87a', 'GIF89a')
    return 'image/webp' if bytes.bytesize >= 12 && bytes[0, 4] == 'RIFF' && bytes[8, 4] == 'WEBP'

    'image/jpeg'
  end

  def prepare_avatar_resync!
    contact.avatar.purge if contact.avatar.attached?

    additional = contact.additional_attributes.stringify_keys
    additional.delete('last_avatar_sync_at')
    additional.delete('avatar_url_hash')
    contact.update_columns(additional_attributes: additional) # rubocop:disable Rails/SkipsModelValidations
  end

  def mark_enriched!
    additional = contact.additional_attributes.stringify_keys.merge(
      EVOLUTION_GO_ENRICHED_AT_KEY => Time.current.utc.iso8601(3)
    )
    contact.update!(additional_attributes: additional)
    true
  end

  def whatsapp_user_exists?(number)
    return true if number.blank?

    response = api_client.user_check(number: number)
    unless response.success?
      Rails.logger.warn(
        "[EVOLUTION_GO] user/check failed for contact #{contact.id}: HTTP #{response.code}"
      )
      # Don't block enrichment/avatar when the check endpoint is unavailable.
      return true
    end

    parse_user_check_exists?(response.parsed_response)
  rescue StandardError => e
    Rails.logger.warn("[EVOLUTION_GO] user/check failed for contact #{contact.id}: #{e.message}")
    true
  end

  # Evolution Go returns `{ data: { Users: [{ IsInWhatsapp: true, ... }] } }`
  # (see docs check-a-user). Older shapes may use top-level `exists`/`Exists`.
  def parse_user_check_exists?(parsed)
    data = nested_response_data(parsed)
    users_flag = users_collection_in_whatsapp?(data[:Users] || data[:users])
    return users_flag unless users_flag.nil?

    exists = data[:exists]
    return exists if exists.in?([true, false])
    return ActiveModel::Type::Boolean.new.cast(data[:Exists]) if data.key?(:Exists)

    # Unknown successful payload — proceed with enrichment rather than skipping avatars.
    true
  end

  def users_collection_in_whatsapp?(users)
    return users.any? { |user| user_in_whatsapp?(user) } if users.is_a?(Array)
    return users.values.any? { |user| user_in_whatsapp?(user) } if users.is_a?(Hash)

    nil
  end

  def user_in_whatsapp?(user)
    return false if user.blank?

    user = user.with_indifferent_access
    flag = user[:IsInWhatsapp]
    flag = user[:isInWhatsapp] if flag.nil?
    flag = user[:exists] if flag.nil?
    flag = user[:Exists] if flag.nil?
    return false if flag.nil?

    ActiveModel::Type::Boolean.new.cast(flag)
  end
end
# rubocop:enable Metrics/ClassLength
