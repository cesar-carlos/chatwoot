# frozen_string_literal: true

class Custom::Whatsapp::Webhooks::EvolutionGoPayloadAdapter
  class << self
    def canonicalize_data(data)
      return {} if data.blank?
      return {} unless data.is_a?(Hash)

      data = data.with_indifferent_access
      info = data[:Info]

      if info.is_a?(Hash)
        return canonicalize_from_info(data, info.with_indifferent_access)
      end

      return data if data[:key].present?

      {}
    end

    def build_key(info)
      chat = info[:Chat].to_s
      sender = info[:Sender].to_s
      sender_alt = (info[:SenderAlt] || info[:RecipientAlt]).to_s
      remote_jid = group_jid_from(chat, sender) || chat.presence || sender
      participant = participant_jid_from_info(info) if group_jid?(remote_jid)

      {
        remoteJid: remote_jid,
        remoteJidAlt: sender_alt.presence,
        participant: participant,
        fromMe: info[:IsFromMe],
        id: info[:ID] || info[:Id],
        addressingMode: info[:AddressingMode].presence || (remote_jid.to_s.end_with?('@lid') ? 'lid' : nil)
      }.compact
    end

    def unwrap_nested_message(message)
      return {} unless message.is_a?(Hash)

      message = message.with_indifferent_access
      inner = message[:ephemeralMessage]&.dig(:message) ||
              message[:viewOnceMessageV2]&.dig(:message) ||
              message[:viewOnceMessage]&.dig(:message)
      inner.presence || message
    end

    def timestamp_from_info(info)
      ts = info[:Timestamp]
      return ts.to_i.to_s if ts.is_a?(Numeric)
      return Time.zone.parse(ts.to_s).to_i.to_s if ts.present?

      nil
    rescue ArgumentError, TypeError
      nil
    end

    private

    def canonicalize_from_info(data, info)
      message = unwrap_nested_message(data[:Message] || {})
      canonical = {
        key: build_key(info),
        message: message,
        pushName: info[:PushName],
        messageTimestamp: timestamp_from_info(info)
      }.compact.with_indifferent_access

      return canonical if data[:key].blank?

      canonical.merge(key: merge_group_key(data[:key].with_indifferent_access, info))
    end

    def merge_group_key(key, info)
      chat = info[:Chat].to_s
      return key unless group_jid?(chat)

      merged = key.dup
      merged[:remoteJid] = chat unless group_jid?(merged[:remoteJid])
      participant = participant_jid_from_info(info)
      merged[:participant] = participant if participant.present? && merged[:participant].blank?
      merged
    end

    def group_jid_from(*jids)
      jids.find { |jid| group_jid?(jid) }
    end

    def participant_jid_from_info(info)
      chat = info[:Chat].to_s
      return unless group_jid?(chat)

      [info[:Sender], info[:SenderAlt]].map(&:to_s).find do |jid|
        jid.present? && !group_jid?(jid)
      end
    end

    def group_jid?(jid)
      jid.to_s.end_with?('@g.us')
    end
  end
end
