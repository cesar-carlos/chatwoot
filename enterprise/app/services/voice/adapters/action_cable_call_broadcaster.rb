# frozen_string_literal: true

module Voice::Adapters
  class ActionCableCallBroadcaster
    def initialize(account_id:, provider:, inbox_id: nil)
      @account_id = account_id
      @provider = provider
      @inbox_id = inbox_id
    end

    def broadcast(call, event, streams:, **extra)
      payload = { event: event, data: base_payload(call).merge(extra) }
      streams.each { |stream| ActionCable.server.broadcast(stream, payload) }
    end

  private

    attr_reader :account_id, :provider, :inbox_id

    def base_payload(call)
      {
        account_id: account_id,
        id: call.id,
        call_id: call.provider_call_id,
        provider: provider,
        conversation_id: call.conversation_id,
        inbox_id: inbox_id || call.inbox_id
      }
    end
  end
end
