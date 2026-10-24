# frozen_string_literal: true

module Custom::Call
  def self.prepended(base)
    base.singleton_class.prepend(ClassMethods)
  end

  # FORK: ICE/TURN servers from GlobalConfigService (VOICE_CALL_ICE_SERVERS / VOICE_CALL_STUN_URLS)
  module ClassMethods
    def default_ice_servers
      raw = GlobalConfigService.load('VOICE_CALL_ICE_SERVERS', nil)
      return parse_ice_servers(raw) if raw.present?

      stun_raw = GlobalConfigService.load('VOICE_CALL_STUN_URLS', Call::DEFAULT_STUN_URL)
      urls = stun_raw.to_s.split(',').filter_map { |u| u.strip.presence }
      [{ urls: urls }]
    end

    private

    def parse_ice_servers(raw)
      parsed = raw.is_a?(String) ? JSON.parse(raw) : raw
      servers = Array(parsed).filter_map { |entry| build_ice_server_entry(entry) }
      servers.presence || [{ urls: Call::DEFAULT_STUN_URL }]
    rescue JSON::ParserError
      [{ urls: Call::DEFAULT_STUN_URL }]
    end

    def build_ice_server_entry(entry)
      entry = entry.with_indifferent_access
      urls = entry[:urls]
      return if urls.blank?

      server = { urls: urls }
      server[:username] = entry[:username] if entry[:username].present?
      server[:credential] = entry[:credential] if entry[:credential].present?
      server
    end
  end

  def recording_url
    return super if recording.attached?

    meta&.dig('record_url') if wavoip?
  end

  def sync_conversation_call_attributes!
    conversation.update!(
      additional_attributes: (conversation.additional_attributes || {}).merge(
        'call_status' => display_status,
        'call_direction' => direction_label
      )
    )
  end
end
