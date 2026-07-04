# frozen_string_literal: true

module Custom::MessageTemplates::HookExecutionService
  def perform
    return unless Custom::Channels::OutboundText.allowed?(inbox.channel)

    super
  end
end
