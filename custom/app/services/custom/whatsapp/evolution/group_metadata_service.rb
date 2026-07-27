# frozen_string_literal: true

class Custom::Whatsapp::Evolution::GroupMetadataService
  CACHE_TTL = 1.hour
  FETCH_ENQUEUE_TTL = 5.minutes.to_i
  SUPPORTED_PROVIDERS = %w[evolution evolution_go].freeze

  pattr_initialize [:channel!]

  def display_name(group_jid, fallback: nil)
    group_jid = group_jid.to_s
    return fallback.to_s if group_jid.blank?

    cached = Rails.cache.read(cache_key(group_jid))
    return cached if cached.present?

    enqueue_metadata_fetch!(group_jid)
    fallback.presence || group_jid.split('@').first
  end

  def warm_cache!(group_jid)
    group_jid = group_jid.to_s
    return if group_jid.blank?

    subject = fetch_subject(group_jid)
    return if subject.blank?

    name = "#{subject} (GROUP)"
    Rails.cache.write(cache_key(group_jid), name, expires_in: CACHE_TTL)
    sync_group_contact_name!(group_jid, name)
    sync_group_avatar!(group_jid) if evolution_go_channel?
    name
  end

  def sync_group_contact_name!(group_jid, name)
    contact = find_group_contact(group_jid)
    return if contact.blank? || name.blank?
    return if contact.name == name

    contact.update!(name: name)
  end

  private

  def sync_group_avatar!(group_jid)
    contact = find_group_contact(group_jid)
    return if contact.blank?
    return if contact.avatar.attached?

    response = api_client.user_avatar(number: group_jid, preview: true)
    unless response&.success?
      log_group_avatar_http_failure!(group_jid, response)
      return
    end

    attach_group_avatar!(contact, response.parsed_response)
  rescue Custom::Whatsapp::EvolutionGo::ApiError => e
    Rails.logger.warn("[EVOLUTION_GO] group avatar fetch failed jid=#{group_jid}: #{e.message}")
  end

  def find_group_contact(group_jid)
    contact = channel.account.contacts.find_by(identifier: group_jid)
    return if contact.blank?
    return unless contact.additional_attributes&.dig(Custom::Whatsapp::Evolution::GroupKeys::IS_WHATSAPP_GROUP_KEY)

    contact
  end

  def attach_group_avatar!(contact, parsed)
    url = avatar_url_from_response(parsed)
    if url.present?
      ::Avatar::AvatarFromUrlJob.perform_later(contact, url)
      return
    end

    base64 = avatar_base64_from_response(parsed)
    if base64.present?
      Custom::Avatar::AvatarFromBase64Job.perform_later(contact, base64)
      return
    end

    Rails.logger.info("[EVOLUTION_GO] group avatar empty payload contact=#{contact.id}")
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

  def log_group_avatar_http_failure!(group_jid, response)
    detail = response&.parsed_response.is_a?(Hash) ? response.parsed_response['error'] : nil
    Rails.logger.warn(
      "[EVOLUTION_GO] group avatar failed jid=#{group_jid}: HTTP #{response&.code} #{detail}"
    )
  end

  def fetch_subject(group_jid) # rubocop:disable Metrics/CyclomaticComplexity
    response = group_info_response(group_jid)
    return unless response&.success?

    parsed = unwrap_group_response(response)
    parsed['subject'].presence ||
      parsed['Name'].presence ||
      parsed.dig('group', 'subject').presence ||
      parsed.dig('group', 'Name').presence ||
      parsed.dig('groupMetadata', 'subject')
  rescue Custom::Whatsapp::Evolution::ApiError, Custom::Whatsapp::EvolutionGo::ApiError => e
    Rails.logger.warn("[#{provider_tag}] group metadata fetch failed jid=#{group_jid}: #{e.message}")
    nil
  end

  def group_info_response(group_jid)
    return unless supported_provider?

    if evolution_go_channel?
      api_client.group_info(group_jid: group_jid)
    else
      api_client.find_group_infos(group_jid: group_jid)
    end
  end

  def unwrap_group_response(response)
    parsed = response.parsed_response || {}
    data = parsed['data']
    return data if data.is_a?(Hash)

    parsed
  end

  def enqueue_metadata_fetch!(group_jid)
    return unless supported_provider?
    return unless claim_metadata_fetch_enqueue!(group_jid)

    Custom::Whatsapp::Evolution::GroupMetadataFetchJob.perform_later(channel.id, group_jid)
  end

  def claim_metadata_fetch_enqueue!(group_jid)
    ::Redis::Alfred.set(
      metadata_fetch_lock_key(group_jid),
      true,
      nx: true,
      ex: FETCH_ENQUEUE_TTL
    )
  end

  def api_client
    if evolution_go_channel?
      Custom::Whatsapp::EvolutionGo::ApiClient.for_channel(channel)
    else
      Custom::Whatsapp::Evolution::ApiClient.for_channel(channel)
    end
  end

  def supported_provider?
    channel.provider.in?(SUPPORTED_PROVIDERS)
  end

  def evolution_go_channel?
    channel.provider == 'evolution_go'
  end

  def provider_tag
    evolution_go_channel? ? 'EVOLUTION_GO' : 'EVOLUTION'
  end

  def cache_key(group_jid)
    "evolution:group_metadata:#{channel.id}:#{group_jid}"
  end

  def metadata_fetch_lock_key(group_jid)
    format(Redis::RedisKeys::EVOLUTION_GROUP_METADATA_FETCH_LOCK, channel_id: channel.id, group_jid: group_jid)
  end
end
