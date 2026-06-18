class Custom::Conversations::ResolveService
  pattr_initialize [:conversation!, :skip_required_attributes]

  def perform
    validate_required_attributes! unless skip_required_attributes
    conversation.update!(status: :resolved) unless conversation.resolved?
  end

  private

  def validate_required_attributes!
    keys = Array(conversation.account.settings['conversation_required_attributes'])
    return if keys.blank?
    return unless conversation.account.feature_enabled?('conversation_required_attributes')

    missing = keys.any? do |key|
      value = conversation.custom_attributes&.dig(key)
      value.nil? || value.to_s.strip.empty?
    end
    raise CustomExceptions::Base.new({ message: 'Missing required conversation attributes' }) if missing
  end
end
