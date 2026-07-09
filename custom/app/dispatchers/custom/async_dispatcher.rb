# frozen_string_literal: true

module Custom::AsyncDispatcher
  def listeners
    super + [
      Custom::Whatsapp::Evolution::TypingListener.instance,
      Custom::Whatsapp::EvolutionGo::TypingListener.instance
    ]
  end
end
