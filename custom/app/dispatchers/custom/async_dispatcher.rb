# frozen_string_literal: true

module Custom::AsyncDispatcher
  def listeners
    super + [Custom::Whatsapp::EvolutionGo::TypingListener.instance]
  end
end
