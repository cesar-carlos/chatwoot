# frozen_string_literal: true

class Custom::Whatsapp::Webhooks::EvolutionGoPayloadAdapter
  class << self
    def canonicalize_data(data)
      return {} if data.blank?
      return {} unless data.is_a?(Hash)

      data = data.with_indifferent_access
      info = data[:Info]

      return canonicalize_from_info(data, info.with_indifferent_access) if info.is_a?(Hash)

      return data if data[:key].present?

      {}
    end

    def build_key(info)
      info = info.with_indifferent_access
      dig = Custom::Whatsapp::EvolutionGo::FieldDig
      from_me = ActiveModel::Type::Boolean.new.cast(dig.dig_field(info, 'IsFromMe', 'isFromMe'))
      chat = dig.dig_field(info, 'Chat', 'chat').to_s
      sender = dig.dig_field(info, 'Sender', 'sender').to_s
      peer_alt = peer_alt_jid(info, from_me: from_me)
      remote_jid = peer_remote_jid(chat: chat, sender: sender, from_me: from_me)
      participant = participant_jid_from_info(info) if group_jid?(remote_jid)

      {
        remoteJid: remote_jid,
        remoteJidAlt: peer_alt.presence,
        participant: participant,
        fromMe: from_me,
        id: dig.dig_field(info, 'ID', 'Id', 'id'),
        addressingMode: dig.dig_field(info, 'AddressingMode', 'addressingMode').presence ||
          (remote_jid.to_s.end_with?('@lid') ? 'lid' : nil)
      }.compact
    end

    def unwrap_nested_message(message) # rubocop:disable Metrics/CyclomaticComplexity
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

    def peer_remote_jid(chat:, sender:, from_me:)
      remote_jid = group_jid_from(chat, sender) || chat.presence || sender
      return remote_jid unless from_me
      return chat if chat.present? && !group_jid?(chat)

      remote_jid
    end

    def peer_alt_jid(info, from_me:)
      if from_me
        (info[:RecipientAlt] || info[:SenderAlt]).to_s
      else
        (info[:SenderAlt] || info[:RecipientAlt]).to_s
      end
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
