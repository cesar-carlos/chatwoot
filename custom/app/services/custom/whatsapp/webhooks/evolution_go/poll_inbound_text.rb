# frozen_string_literal: true

module Custom::Whatsapp::Webhooks::EvolutionGo::PollInboundText
  POLL_PLACEHOLDER = '[Poll]'
  POLL_CREATION_KEYS = %w[pollCreationMessage pollCreationMessageV2 pollCreationMessageV3].freeze

  private

  def blank_poll_update?(message)
    message = (message || {}).with_indifferent_access
    poll = inbound_field_dig.dig_field(message, 'pollUpdateMessage')
    return false unless poll.is_a?(Hash)

    poll_vote_label(poll).blank?
  end

  def poll_creation_text(message)
    poll = poll_creation_node(message)
    return unless poll.is_a?(Hash)

    poll = poll.with_indifferent_access
    question = inbound_field_dig.dig_field(poll, 'name').to_s.presence ||
               inbound_field_dig.dig_field(poll, 'question').to_s.presence
    options = poll_option_names(inbound_field_dig.dig_field(poll, 'options')).map { |option| "- #{option}" }
    [question, *options].compact.join("\n\n").presence || POLL_PLACEHOLDER
  end

  def poll_creation_node(message)
    POLL_CREATION_KEYS.lazy.filter_map do |key|
      node = inbound_field_dig.dig_field(message, key)
      node if node.is_a?(Hash)
    end.first
  end

  def poll_vote_text_from_message(message)
    poll = inbound_field_dig.dig_field(message, 'pollUpdateMessage')
    return unless poll.is_a?(Hash)

    poll_vote_label(poll)
  end

  def poll_vote_label(poll)
    poll = poll.with_indifferent_access
    vote = inbound_field_dig.dig_field(poll, 'vote')
    names = vote.is_a?(Hash) ? poll_option_names_from_vote(vote.with_indifferent_access) : []
    names = poll_option_names_from_vote(poll) if names.blank?
    names.join(', ').presence
  end

  def poll_option_names_from_vote(hash)
    selected = inbound_field_dig.dig_field(hash, 'selectedOptions') ||
               inbound_field_dig.dig_field(hash, 'selectedOption') ||
               inbound_field_dig.dig_field(hash, 'optionName')
    poll_option_names(selected)
  end

  def poll_option_names(options)
    Array.wrap(options).filter_map do |option|
      case option
      when String
        option.presence
      when Hash
        inbound_field_dig.dig_field(option.with_indifferent_access, 'optionName').to_s.presence ||
          inbound_field_dig.dig_field(option.with_indifferent_access, 'name').to_s.presence
      end
    end
  end
end
