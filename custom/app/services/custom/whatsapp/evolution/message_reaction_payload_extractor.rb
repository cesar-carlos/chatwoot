# frozen_string_literal: true

module Custom::Whatsapp::Evolution::MessageReactionPayloadExtractor
  module_function

  def extract_reaction_payload(data)
    data = unwrap_message((data || {}).with_indifferent_access)
    message = (data[:message] || {}).with_indifferent_access
    reaction = message[:reactionMessage] || message['reactionMessage']
    return if reaction.blank?

    reaction = reaction.with_indifferent_access
    target_key = normalize_key(reaction[:key] || reaction['key'])
    return if target_key.blank? || target_key[:id].blank?

    envelope_key = normalize_key(data[:key] || data['key'])
    text = reaction_text(reaction)
    {
      key: target_key,
      text: text,
      remove: removal?(text),
      reaction_message_id: envelope_key&.dig(:id),
      from_me: ActiveModel::Type::Boolean.new.cast(envelope_key&.dig(:fromMe)),
      participant: envelope_key&.dig(:participant) || target_key[:participant]
    }.compact
  end

  def unwrap_message(data)
    message = data[:message]
    return data unless message.is_a?(Hash)

    inner = message.with_indifferent_access
    nested = inner.dig(:ephemeralMessage, :message) ||
             inner.dig(:viewOnceMessageV2, :message) ||
             inner.dig('ephemeralMessage', 'message') ||
             inner.dig('viewOnceMessageV2', 'message')
    return data if nested.blank?

    data.merge(message: nested)
  end

  def normalize_key(key)
    return if key.blank?

    key = key.with_indifferent_access
    {
      id: key[:id].presence,
      remoteJid: key[:remoteJid].presence,
      fromMe: key[:fromMe],
      participant: key[:participant].presence
    }.compact
  end

  def reaction_text(reaction)
    reaction[:text].presence || reaction['text'].presence || reaction[:Text].to_s
  end

  def removal?(text)
    text.blank? || text.to_s.strip.casecmp('remove').zero?
  end
end
