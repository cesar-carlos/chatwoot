# frozen_string_literal: true

class Custom::Whatsapp::Evolution::GroupMetadataService
  CACHE_TTL = 1.hour

  pattr_initialize [:channel!]

  def display_name(group_jid, fallback: nil)
    group_jid = group_jid.to_s
    return fallback.to_s if group_jid.blank?

    cached = Rails.cache.read(cache_key(group_jid))
    return cached if cached.present?

    subject = fetch_subject(group_jid)
    name = if subject.present?
             "#{subject} (GROUP)"
           else
             fallback.presence || group_jid.split('@').first
           end
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

  def api_client
    Custom::Whatsapp::Evolution::ApiClient.for_channel(channel)
  end

  def cache_key(group_jid)
    "evolution:group_metadata:#{channel.id}:#{group_jid}"
  end
end
