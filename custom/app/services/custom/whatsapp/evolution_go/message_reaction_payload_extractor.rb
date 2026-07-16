# frozen_string_literal: true

module Custom::Whatsapp::EvolutionGo::MessageReactionPayloadExtractor
  module_function

  def extract_reaction_payload(data)
    canonical = Custom::Whatsapp::Webhooks::EvolutionGoPayloadAdapter.canonicalize_data(data)
    raw = (data || {}).with_indifferent_access
    message = (canonical[:message] || canonical['message'] || {}).with_indifferent_access
    reaction = message[:reactionMessage] || message['reactionMessage']
    return if reaction.blank?

    reaction = reaction.with_indifferent_access
    target_key = Custom::Whatsapp::EvolutionGo::MessageDeletePayloadExtractor.normalize_key(
      reaction[:key] || reaction['key']
    )
    return if target_key.blank? || target_key[:id].blank?

    envelope_key = Custom::Whatsapp::EvolutionGo::MessageDeletePayloadExtractor.normalize_key(
      canonical[:key] || canonical['key'] || raw[:key] || raw['key']
    )

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

  def reaction_text(reaction)
    value = Custom::Whatsapp::EvolutionGo::FieldDig.dig_field(reaction, 'text', 'Text')
    value.to_s
  end

  def removal?(text)
    text.blank? || text.to_s.strip.casecmp('remove').zero?
  end
end
