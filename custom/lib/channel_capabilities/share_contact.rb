module ChannelCapabilities::ShareContact
  SHARE_CONTACT_CHANNELS = %w[Channel::Whatsapp Channel::Telegram].freeze

  module_function

  def supports?(channel)
    SHARE_CONTACT_CHANNELS.include?(channel.class.name)
  end
end
