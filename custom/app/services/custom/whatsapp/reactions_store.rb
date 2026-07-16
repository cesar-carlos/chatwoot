# frozen_string_literal: true

module Custom::Whatsapp::ReactionsStore
  REACTIONS_KEY = 'reactions'
  BUSINESS_ACTOR_KEY = 'user:self'

  module_function

  def apply!(message, emoji:, actor_key:, from:, actor_id: nil, reaction_message_id: nil, **_extra)
    attrs = (message.content_attributes || {}).stringify_keys
    reactions = Array.wrap(attrs[REACTIONS_KEY]).map { |entry| entry.stringify_keys }
    reactions.reject! { |entry| same_actor?(entry, actor_key: actor_key, from: from, actor_id: actor_id) }

    reactions << {
      'emoji' => emoji.to_s,
      'from' => from.to_s,
      'actor_id' => actor_id,
      'actor_key' => actor_key.to_s,
      'reaction_message_id' => reaction_message_id,
      'target_message_id' => message.source_id,
      'updated_at' => Time.current.utc.iso8601(3)
    }.compact

    message.update!(content_attributes: attrs.merge(REACTIONS_KEY => reactions))
  end

  def remove_actor!(message, actor_key:, from: nil, actor_id: nil)
    attrs = (message.content_attributes || {}).stringify_keys
    reactions = Array.wrap(attrs[REACTIONS_KEY]).map { |entry| entry.stringify_keys }
    reactions.reject! { |entry| same_actor?(entry, actor_key: actor_key, from: from, actor_id: actor_id) }
    message.update!(content_attributes: attrs.merge(REACTIONS_KEY => reactions))
  end

  def same_actor?(entry, actor_key:, from: nil, actor_id: nil)
    entry = entry.stringify_keys
    return true if actor_key.present? && entry['actor_key'] == actor_key.to_s
    # Legacy outbound used user:<id>; treat as same business actor when merging with user:self
    if actor_key.to_s == BUSINESS_ACTOR_KEY && entry['from'] == 'user'
      return true
    end
    return true if from.present? && actor_id.present? &&
                   entry['from'] == from.to_s && entry['actor_id'].to_s == actor_id.to_s

    false
  end

  def business_actor(actor_id: nil)
    {
      from: 'user',
      actor_id: actor_id,
      actor_key: BUSINESS_ACTOR_KEY
    }.compact
  end
end
