module Custom::MessageSearch::FromFilter
  module_function

  def apply(scope, from)
    case from.to_s.strip.presence
    when 'private'
      scope.where(private: true)
    when 'contact'
      scope.where(sender_type: 'Contact')
    when 'agent'
      scope.where(sender_type: 'User')
    when /\Acontact:(\d+)\z/
      scope.where(sender_type: 'Contact', sender_id: Regexp.last_match(1).to_i)
    when /\Aagent:(\d+)\z/
      scope.where(sender_type: 'User', sender_id: Regexp.last_match(1).to_i)
    else
      scope
    end
  end

  def opensearch_conditions(conversation, from)
    conditions = {
      account_id: conversation.account_id,
      conversation_id: conversation.id,
      message_type: searchable_message_types,
      deleted: false
    }

    apply_opensearch_from!(conditions, from)
    conditions
  end

  def apply_opensearch_from!(conditions, from)
    case from.to_s.strip.presence
    when 'private'
      conditions[:private] = true
    when 'contact'
      conditions[:sender_type] = 'Contact'
    when 'agent'
      conditions[:sender_type] = 'User'
    when /\Acontact:(\d+)\z/
      conditions[:sender_type] = 'Contact'
      conditions[:sender_id] = Regexp.last_match(1).to_i
    when /\Aagent:(\d+)\z/
      conditions[:sender_type] = 'User'
      conditions[:sender_id] = Regexp.last_match(1).to_i
    end
  end

  def searchable_message_types
    %i[incoming outgoing template].map { |type| Message.message_types[type] }
  end
end
