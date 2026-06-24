# frozen_string_literal: true

class Wavoip::Calls::RingEscalationScheduler
  def initialize(call:)
    @call = call
    @inbox = call.inbox
  end

  def schedule
    timeout = inbox.channel.ring_timeout_seconds
    return unless timeout.positive?

    Wavoip::EscalateRingJob.set(wait: timeout.seconds).perform_later(call.id)
  end

  private

  attr_reader :call, :inbox
end
