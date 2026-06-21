# frozen_string_literal: true

class MessagingProvider::Registry
  class << self
    def register(key, service_class)
      providers[key.to_s] = service_class
    end

    def resolve(key, whatsapp_channel:)
      klass = providers[key.to_s]
      klass&.new(whatsapp_channel: whatsapp_channel)
    end

    def registered?(key)
      providers.key?(key.to_s)
    end

    private

    def providers
      @providers ||= {}
    end
  end
end
