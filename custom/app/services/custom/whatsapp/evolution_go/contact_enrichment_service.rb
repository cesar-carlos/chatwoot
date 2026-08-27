# frozen_string_literal: true

# rubocop:disable Metrics/ClassLength -- enrichment mirrors Evolution Go contact profile fetch
class Custom::Whatsapp::EvolutionGo::ContactEnrichmentService
  ENRICHMENT_COOLDOWN = 24.hours
  # Missing/privacy (no photo URL) — avoid re-enqueueing on every inbound.
  AVATAR_RETRY_COOLDOWN = 6.hours
  # Transient Evolution Go /user/avatar timeouts — short backoff (not 6h).
  AVATAR_TIMEOUT_RETRY_COOLDOWN = 30.minutes
  # Manual Sync / Refresh — Evolution Go often times out; retry within one job.
  FORCE_AVATAR_ATTEMPTS = 3
  FORCE_AVATAR_RETRY_WAIT = 1.5
  # Non-force inbound: primary + one fallback. Force: try every candidate.
  INBOUND_AVATAR_CANDIDATE_LIMIT = 2
  WHATSAPP_STATUS_KEY = 'whatsapp_status'
  EVOLUTION_GO_PUSH_NAME_KEY = 'evolution_go_push_name'
  EVOLUTION_GO_REMOTE_JID_KEY = 'evolution_go_remote_jid'
  EVOLUTION_GO_ENRICHED_AT_KEY = 'evolution_go_enriched_at'
  EVOLUTION_GO_AVATAR_ATTEMPTED_AT_KEY = 'evolution_go_avatar_attempted_at'
  EVOLUTION_GO_AVATAR_TIMEOUT_AT_KEY = 'evolution_go_avatar_timeout_at'
  EVOLUTION_GO_PICTURE_ID_KEY = 'evolution_go_picture_id'

  def self.should_enqueue?(contact:, remote_jid: nil, push_name: nil, force: false)
    return true if ActiveModel::Type::Boolean.new.cast(force)

    additional = contact.additional_attributes.to_h.stringify_keys
    return true if remote_jid.to_s.present? && additional[EVOLUTION_GO_REMOTE_JID_KEY] != remote_jid.to_s
    return true if push_name_changed?(contact, push_name)
    # Missing avatar used to always enqueue; that saturated Sidekiq when Go hung on /user/avatar.
    return true if !contact.avatar.attached? && can_retry_missing_avatar?(contact)

    enrichment_stale?(contact)
  end

  def self.enrichment_stale?(contact)
    enriched_at = contact.additional_attributes.to_h[EVOLUTION_GO_ENRICHED_AT_KEY]
    return true if enriched_at.blank?

    Time.zone.parse(enriched_at) <= ENRICHMENT_COOLDOWN.ago
  rescue ArgumentError
    true
  end

  def self.can_retry_missing_avatar?(contact)
    avatar_attempt_stale?(contact) && avatar_timeout_stale?(contact)
  end

  def self.avatar_attempt_stale?(contact)
    attempted_at = contact.additional_attributes.to_h[EVOLUTION_GO_AVATAR_ATTEMPTED_AT_KEY]
    return true if attempted_at.blank?

    Time.zone.parse(attempted_at) <= AVATAR_RETRY_COOLDOWN.ago
  rescue ArgumentError
    true
  end

  def self.avatar_timeout_stale?(contact)
    timeout_at = contact.additional_attributes.to_h[EVOLUTION_GO_AVATAR_TIMEOUT_AT_KEY]
    return true if timeout_at.blank?

    Time.zone.parse(timeout_at) <= AVATAR_TIMEOUT_RETRY_COOLDOWN.ago
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
    return sync_whatsapp_group! if whatsapp_group_contact?

    persist_remote_jid!
    update_name_from_push_name!
    outcome = fetch_and_apply_profile!
    # Rate-limit means WhatsApp rejected usync — do not stamp enriched_at (24h cooldown).
    mark_enriched! unless outcome == :rate_limited
  end

  private

  attr_reader :channel, :contact, :force

  def whatsapp_group_contact?
    attrs = contact.additional_attributes.to_h.stringify_keys
    return true if ActiveModel::Type::Boolean.new.cast(
      attrs[Custom::Whatsapp::Evolution::GroupKeys::IS_WHATSAPP_GROUP_KEY]
    )

    group_jid_for_contact.present?
  end

  def group_jid_for_contact
    attrs = contact.additional_attributes.to_h.stringify_keys
    [
      attrs[Custom::Whatsapp::Evolution::GroupKeys::EVOLUTION_GROUP_JID_KEY],
      contact.identifier,
      @remote_jid,
      stored_remote_jid
    ].find { |value| Custom::Whatsapp::Evolution::GroupContactService.group_jid?(value) }.to_s.presence
  end

  # Bulk refresh / mistaken 1:1 enqueue still syncs groups via /group/info + avatar.
  def sync_whatsapp_group!
    group_jid = group_jid_for_contact
    return if group_jid.blank?

    Custom::Whatsapp::Evolution::GroupMetadataService.new(channel: channel).warm_cache!(group_jid)
  end

  def api_client
    @api_client ||= Custom::Whatsapp::EvolutionGo::ApiClient.for_channel(channel)
  end

  # Prefer LID / stored WA JID. Never invent phone@s.whatsapp.net from the contact
  # phone — BR numbers with the extra 9 return HTTP 200 with empty Users fields.
  def user_info_query
    lid = first_lid_candidate
    return lid if lid.present?

    wa_jid = [@remote_jid, stored_remote_jid].find { |value| value.to_s.end_with?('@s.whatsapp.net') }
    return wa_jid if wa_jid.present?

    contact_phone_digits.presence
  end

  def lookup_number
    digits = contact_phone_digits
    return digits if digits.present?

    jid = @remote_jid.presence || stored_remote_jid.presence || contact.identifier.to_s
    jid.to_s.split('@').first.presence
  end

  # Same priority as user_info_query for /user/avatar (LID first — phone BR often times out).
  def avatar_query_candidates
    candidates = []
    lid = first_lid_candidate
    candidates << lid if lid.present?

    wa_jid = [@remote_jid, stored_remote_jid].find { |value| value.to_s.end_with?('@s.whatsapp.net') }
    if wa_jid.present?
      candidates << wa_jid
      candidates << wa_jid.to_s.split('@').first
    elsif contact_phone_digits.present?
      candidates << contact_phone_digits
    end

    candidates.filter_map { |value| value.to_s.presence }.uniq
  end

  def first_lid_candidate
    [@remote_jid, stored_remote_jid, contact.identifier.to_s].find { |value| value.to_s.end_with?('@lid') }
  end

  def stored_remote_jid
    contact.additional_attributes.to_h.stringify_keys[EVOLUTION_GO_REMOTE_JID_KEY].to_s
  end

  def contact_phone_digits
    contact.phone_number.to_s.gsub(/\D/, '')
  end

  def persist_remote_jid!
    return if @remote_jid.blank?

    updates = {}
    updates[:identifier] = @remote_jid if @remote_jid.end_with?('@lid') && contact.identifier != @remote_jid && lid_available?(@remote_jid)

    additional = contact.additional_attributes.stringify_keys
    merged = Custom::Whatsapp::EvolutionGo::JidResolver.merge_addressing_jid(
      additional[EVOLUTION_GO_REMOTE_JID_KEY],
      @remote_jid
    )
    return if additional[EVOLUTION_GO_REMOTE_JID_KEY] == merged && updates.blank?

    additional[EVOLUTION_GO_REMOTE_JID_KEY] = merged
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
    enrich_profile_and_avatar!
  rescue StandardError => e
    handle_profile_enrichment_error!(e)
  end

  def enrich_profile_and_avatar!
    query = user_info_query
    number = lookup_number
    return false if query.blank? && number.blank?
    return false if skip_missing_whatsapp_user?(number)

    profile = fetch_user_profile(query)
    return :rate_limited if profile == :rate_limited

    applied = apply_profile(profile, query) if profile.present?
    apply_avatar_after_profile!(profile, applied)
  end

  def apply_avatar_after_profile!(profile, applied)
    avatar_outcome = fetch_and_apply_avatar!(
      picture_url: profile_picture_url(profile),
      picture_id: profile_picture_id(profile)
    )
    return :rate_limited if avatar_outcome == :rate_limited

    avatar_outcome || applied
  end

  # /user/check is another usync query — skip on forced refresh to cut API pressure.
  def skip_missing_whatsapp_user?(number)
    return false if force
    return false if whatsapp_user_exists?(number)

    mark_avatar_attempted! unless contact.avatar.attached?
    true
  end

  def handle_profile_enrichment_error!(error)
    Rails.logger.warn("[EVOLUTION_GO] contact enrichment failed for contact #{contact.id}: #{error.message}")
    contact.reload if contact.persisted?
    return :rate_limited if rate_limited_error?(error)

    mark_avatar_failure_from_error!(error) unless contact.avatar.attached?
    false
  end

  def mark_avatar_failure_from_error!(error)
    if network_timeout_error?(error)
      mark_avatar_timeout!
    else
      mark_avatar_attempted!
    end
  end

  def fetch_user_profile(query)
    return if query.blank?

    profile = request_user_profile(query)
    return profile if profile == :rate_limited
    return profile if profile_present?(profile)

    # Empty Users payload often means phone@s.whatsapp.net with a non-canonical BR digit.
    digits = contact_phone_digits
    return if digits.blank? || digits == query.to_s

    request_user_profile(digits)
  end

  def request_user_profile(query)
    response = api_client.user_info(numbers: [query])
    unless response.success?
      detail = Custom::Whatsapp::EvolutionGo::ApiError.extract_message(response.parsed_response)
      Rails.logger.warn(
        "[EVOLUTION_GO] user/info failed for contact #{contact.id}: HTTP #{response.code} #{detail}"
      )
      return :rate_limited if rate_limited_response?(response)

      return
    end

    profile = extract_user_profile(response.parsed_response, query)
    profile_present?(profile) ? profile : nil
  end

  def extract_user_profile(parsed, jid)
    data = parsed.is_a?(Hash) ? (parsed['data'] || parsed) : {}
    users = data['Users'] || data['users'] || {}
    users[jid] || users[jid.to_s] || users.values.first
  end

  def profile_present?(profile)
    return false if profile.blank?

    profile = profile.with_indifferent_access
    profile[:Status].to_s.strip.present? ||
      profile[:PictureURL].to_s.present? ||
      profile[:PictureID].to_s.present? ||
      profile[:LID].to_s.present? ||
      profile[:VerifiedName].to_s.strip.present? ||
      Array(profile[:Devices]).any?
  end

  def profile_picture_url(profile)
    return if profile.blank?

    url = profile.with_indifferent_access[:PictureURL].to_s.strip
    url.start_with?('http') ? url : nil
  end

  def profile_picture_id(profile)
    return if profile.blank?

    profile.with_indifferent_access[:PictureID].to_s.strip.presence
  end

  def apply_profile(profile, jid) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
    return false if profile.blank?

    updates = {}
    additional = contact.additional_attributes.stringify_keys
    name = profile['VerifiedName'].to_s.strip.presence
    if name.present? && name_updatable? && contact.name != name
      updates[:name] = name
      additional[EVOLUTION_GO_PUSH_NAME_KEY] = name
    end

    status = profile['Status'].to_s.strip.presence
    if status.present?
      custom = contact.custom_attributes.stringify_keys
      custom[WHATSAPP_STATUS_KEY] = status
      updates[:custom_attributes] = custom
    end

    lid = profile['LID'].to_s.presence
    updates[:identifier] = lid if lid.present? && lid.end_with?('@lid') && contact.identifier != lid && lid_available?(lid)

    picture_id = profile_picture_id(profile)
    additional[EVOLUTION_GO_PICTURE_ID_KEY] = picture_id if picture_id.present?

    remote = canonical_remote_jid(profile, jid)
    incoming_jid = lid.to_s.end_with?('@lid') ? lid : remote
    if incoming_jid.present?
      additional[EVOLUTION_GO_REMOTE_JID_KEY] = Custom::Whatsapp::EvolutionGo::JidResolver.merge_addressing_jid(
        additional[EVOLUTION_GO_REMOTE_JID_KEY],
        incoming_jid
      )
    end
    updates[:additional_attributes] = additional if additional != contact.additional_attributes.stringify_keys
    contact.update!(updates) if updates.present?
    true
  end

  def lid_available?(lid)
    !contact.account.contacts.where(identifier: lid).where.not(id: contact.id).exists?
  end

  def canonical_remote_jid(profile, jid)
    return jid.to_s if jid.to_s.end_with?('@lid', '@s.whatsapp.net')

    Array(profile.with_indifferent_access[:Devices]).map(&:to_s).find { |device| device.include?('@') }
  end

  def fetch_and_apply_avatar!(picture_url: nil, picture_id: nil)
    attached_avatar_short_circuit = attached_avatar_fetch_outcome(picture_id)
    return attached_avatar_short_circuit unless attached_avatar_short_circuit.nil?

    return true if attach_from_picture_url!(picture_url, picture_id)

    fetch_avatar_from_candidates!(picture_id)
  end

  # nil = continue fetch; true/false = done
  def attached_avatar_fetch_outcome(picture_id)
    return nil unless contact.avatar.attached?
    return false unless force
    # Same PictureID → photo unchanged; skip CDN/usync on forced refresh.
    return true if unchanged_attached_avatar?(picture_id)

    nil
  end

  def attach_from_picture_url!(picture_url, picture_id)
    return false if picture_url.blank?

    attached = attach_avatar_from_url!(picture_url)
    store_picture_id!(picture_id) if attached && picture_id.present?
    attached
  end

  def unchanged_attached_avatar?(picture_id)
    picture_id.present? && stored_picture_id == picture_id
  end

  def fetch_avatar_from_candidates!(picture_id)
    candidates = avatar_query_candidates
    return false if candidates.blank?

    last_outcome = false
    candidates.first(avatar_candidate_limit(candidates.size)).each do |candidate|
      outcome = request_and_attach_avatar!(candidate, picture_id: picture_id)
      return true if outcome == true
      return :rate_limited if outcome == :rate_limited

      last_outcome = outcome
    end

    finalize_avatar_miss!(last_outcome)
    false
  end

  def avatar_candidate_limit(total)
    force ? total : INBOUND_AVATAR_CANDIDATE_LIMIT
  end

  # Defer cooldowns until all avatar query candidates are exhausted — otherwise an empty
  # LID response would stamp 6h before the PN fallback runs.
  def finalize_avatar_miss!(last_outcome)
    case last_outcome
    when :timeout
      mark_avatar_timeout!
    when false
      mark_avatar_attempted!
    end
  end

  def request_and_attach_avatar!(number, picture_id: nil)
    return false if number.blank?

    last_outcome = false
    avatar_attempt_limit.times do |index|
      last_outcome = request_avatar_once!(number, picture_id: picture_id)
      return last_outcome if last_outcome == true || last_outcome == :rate_limited
      break if last_outcome == false

      # Timeout only — brief pause then retry (manual Sync / Refresh).
      wait_before_avatar_retry if force && index < avatar_attempt_limit - 1
    end

    last_outcome
  end

  def avatar_attempt_limit
    force ? FORCE_AVATAR_ATTEMPTS : 1
  end

  def wait_before_avatar_retry
    Kernel.sleep(FORCE_AVATAR_RETRY_WAIT)
  end

  def request_avatar_once!(number, picture_id: nil)
    response = api_client.user_avatar(number: number, preview: true)
    return handle_avatar_success_response!(response, picture_id) if response.success?
    return :rate_limited if rate_limited_response?(response)

    # HTTP miss without marking — finalize_avatar_miss! decides after fallbacks.
    log_avatar_http_failure!(response)
    false
  rescue Custom::Whatsapp::EvolutionGo::ApiError, *Custom::Whatsapp::EvolutionGo::ApiClient::NETWORK_ERRORS => e
    handle_avatar_request_error!(e)
  end

  def handle_avatar_success_response!(response, picture_id)
    attached = attach_avatar_from_response!(response.parsed_response)
    store_picture_id!(picture_id) if attached && picture_id.present?
    attached
  end

  def handle_avatar_request_error!(error)
    Rails.logger.warn("[EVOLUTION_GO] user/avatar error for contact #{contact.id}: #{error.message}")
    return :rate_limited if rate_limited_error?(error)
    return :timeout if network_timeout_error?(error)

    false
  end

  def network_timeout_error?(error)
    return true if error.is_a?(Net::ReadTimeout) || error.is_a?(Net::OpenTimeout)
    return true if error.cause.is_a?(Net::ReadTimeout) || error.cause.is_a?(Net::OpenTimeout)

    error.message.to_s.match?(/ReadTimeout|OpenTimeout|execution expired/i)
  end

  def stored_picture_id
    contact.additional_attributes.to_h.stringify_keys[EVOLUTION_GO_PICTURE_ID_KEY].to_s
  end

  def store_picture_id!(picture_id)
    return if picture_id.blank?
    return if stored_picture_id == picture_id.to_s

    additional = contact.additional_attributes.stringify_keys.merge(EVOLUTION_GO_PICTURE_ID_KEY => picture_id.to_s)
    contact.update!(additional_attributes: additional)
  end

  def log_avatar_http_failure!(response)
    detail = Custom::Whatsapp::EvolutionGo::ApiError.extract_message(response.parsed_response)
    Rails.logger.warn(
      "[EVOLUTION_GO] user/avatar failed for contact #{contact.id}: HTTP #{response.code} #{detail}"
    )
  end

  def attach_avatar_from_url!(url)
    return false if url.blank?
    return false if contact.avatar.attached? && !force

    prepare_avatar_resync! if force
    clear_avatar_attempt!
    enqueue_or_run_avatar_from_url!(url)
  end

  def enqueue_or_run_avatar_from_url!(url)
    # Force Sync: download inline so UI polls see the avatar without a second Sidekiq hop.
    # (Same success contract as perform_later — job owns CDN attach failures.)
    if force
      ::Avatar::AvatarFromUrlJob.perform_now(contact, url)
    else
      ::Avatar::AvatarFromUrlJob.perform_later(contact, url)
    end
    true
  end

  def rate_limited_response?(response)
    detail = Custom::Whatsapp::EvolutionGo::ApiError.extract_message(response.parsed_response)
    rate_limited_message?(detail) || response.code.to_i == 429
  end

  def rate_limited_error?(error)
    rate_limited_message?(error.message)
  end

  def rate_limited_message?(text)
    text.to_s.match?(/rate-?overlimit|rate.?limit|status 429/i)
  end

  def attach_avatar_from_response!(parsed)
    url = avatar_url_from_response(parsed)
    if url.present?
      prepare_avatar_resync! if force
      clear_avatar_attempt!
      return enqueue_or_run_avatar_from_url!(url)
    end

    base64 = avatar_base64_from_response(parsed)
    if base64.present?
      attached = attach_avatar_from_base64!(base64)
      clear_avatar_attempt! if attached
      return attached
    end

    Rails.logger.info("[EVOLUTION_GO] user/avatar returned no URL/base64 for contact #{contact.id}")
    false
  end

  def mark_avatar_attempted!
    additional = contact.additional_attributes.stringify_keys
    additional.delete(EVOLUTION_GO_AVATAR_TIMEOUT_AT_KEY)
    additional[EVOLUTION_GO_AVATAR_ATTEMPTED_AT_KEY] = Time.current.utc.iso8601(3)
    contact.update!(additional_attributes: additional)
  end

  def mark_avatar_timeout!
    additional = contact.additional_attributes.stringify_keys.merge(
      EVOLUTION_GO_AVATAR_TIMEOUT_AT_KEY => Time.current.utc.iso8601(3)
    )
    contact.update!(additional_attributes: additional)
  end

  def clear_avatar_attempt!
    additional = contact.additional_attributes.stringify_keys
    changed = false
    if additional.key?(EVOLUTION_GO_AVATAR_ATTEMPTED_AT_KEY)
      additional.delete(EVOLUTION_GO_AVATAR_ATTEMPTED_AT_KEY)
      changed = true
    end
    if additional.key?(EVOLUTION_GO_AVATAR_TIMEOUT_AT_KEY)
      additional.delete(EVOLUTION_GO_AVATAR_TIMEOUT_AT_KEY)
      changed = true
    end
    return unless changed

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
