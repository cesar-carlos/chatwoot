# frozen_string_literal: true

class Custom::Whatsapp::Evolution::GroupMetadataService
  CACHE_TTL = 1.hour
  FETCH_ENQUEUE_TTL = 5.minutes.to_i

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

  def fetch_subject(group_jid)
    response = api_client.find_group_infos(group_jid: group_jid)
    return unless response.success?

    parsed = response.parsed_response || {}
    parsed['subject'].presence ||
      parsed.dig('group', 'subject').presence ||
      parsed.dig('groupMetadata', 'subject')
  rescue Custom::Whatsapp::Evolution::ApiError => e
    Rails.logger.warn("[EVOLUTION] group metadata fetch failed jid=#{group_jid}: #{e.message}")
    nil
  end

  def enqueue_metadata_fetch!(group_jid)
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
    Custom::Whatsapp::Evolution::ApiClient.for_channel(channel)
  end

  def cache_key(group_jid)
    "evolution:group_metadata:#{channel.id}:#{group_jid}"
  end

  def metadata_fetch_lock_key(group_jid)
    format(Redis::RedisKeys::EVOLUTION_GROUP_METADATA_FETCH_LOCK, channel_id: channel.id, group_jid: group_jid)
  end
end
