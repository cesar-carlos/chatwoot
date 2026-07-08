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
    name
  end

  private

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
