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
      group_chat = group_jid?(remote_jid)
      participant = participant_jid_from_info(info) if group_chat

      {
        remoteJid: remote_jid,
        # Participant PN belongs in `participant` for groups — never as remoteJidAlt
        # (LID addressing would otherwise rewrite @g.us to the member phone).
        remoteJidAlt: group_chat ? nil : peer_alt.presence,
        participant: participant,
        fromMe: from_me,
        id: dig.dig_field(info, 'ID', 'Id', 'id'),
        addressingMode: dig.dig_field(info, 'AddressingMode', 'addressingMode').presence ||
          (remote_jid.to_s.end_with?('@lid') ? 'lid' : nil)
      }.compact
    end

    # WhatsApp / Evolution Go nest real payloads under wrappers. Documents with
    # caption arrive as documentWithCaptionMessage → message → documentMessage.
    NESTED_MESSAGE_WRAPPERS = %i[
      ephemeralMessage
      viewOnceMessage
      viewOnceMessageV2
      viewOnceMessageV2Extension
      documentWithCaptionMessage
      botInvokeMessage
    ].freeze

    def unwrap_nested_message(message)
      return {} unless message.is_a?(Hash)

      current = message.with_indifferent_access
      loop do
        wrapper = NESTED_MESSAGE_WRAPPERS.find { |key| current[key].is_a?(Hash) }
        break unless wrapper

        inner = current[wrapper][:message] || current[wrapper]['message']
        break unless inner.is_a?(Hash)

        current = inner.with_indifferent_access
      end
      current
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

      apply_unavailable_flags!(canonical, data)

      return canonical if data[:key].blank?

      canonical.merge(key: merge_group_key(data[:key].with_indifferent_access, info))
    end

    def apply_unavailable_flags!(canonical, data)
      dig = Custom::Whatsapp::EvolutionGo::FieldDig
      unavailable = ActiveModel::Type::Boolean.new.cast(
        dig.dig_field(data, 'IsUnavailable', 'isUnavailable')
      )
      return unless unavailable

      canonical[:is_unavailable] = true
      unavailable_type = dig.dig_field(data, 'UnavailableType', 'unavailableType').to_s.presence
      canonical[:unavailable_type] = unavailable_type if unavailable_type
    end

    def merge_group_key(key, info)
      chat = info[:Chat].to_s
      return key unless group_jid?(chat)

      merged = key.dup
      merged[:remoteJid] = chat unless group_jid?(merged[:remoteJid])
      merged.delete(:remoteJidAlt)
      merged.delete('remoteJidAlt')
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

      # Prefer clean PN (SenderAlt) over device JID (Sender user:device@…).
      candidates = [info[:SenderAlt], info[:Sender], info[:RecipientAlt]].map(&:to_s)
      pn = candidates.find { |jid| phone_jid?(jid) }
      return pn if pn.present?

      candidates.find { |jid| jid.present? && !group_jid?(jid) }
    end

    def phone_jid?(jid)
      jid = jid.to_s
      return false if jid.blank? || group_jid?(jid) || jid.end_with?('@lid')

      user = jid.split('@').first.to_s.split(':', 2).first
      user.match?(/\A\d+\z/) && jid.include?('@')
    end

    def group_jid?(jid)
      jid.to_s.end_with?('@g.us')
    end
  end
end
