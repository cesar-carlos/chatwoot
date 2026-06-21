# frozen_string_literal: true

module Custom::Whatsapp::Evolution::MarkdownConverter
  module_function

  # Chatwoot markdown → WhatsApp formatting (mirrors Evolution chatwoot.service.ts outbound).
  def outbound(text)
    return text if text.blank?

    text
      .gsub(/(?<!\*)\*((?!\s)([^\n*]+?)(?<!\s))\*(?!\*)/, '_\1_')
      .gsub(/\*{2}((?!\s)([^\n*]+?)(?<!\s))\*{2}/, '*\1*')
      .gsub(/~{2}((?!\s)([^\n*]+?)(?<!\s))~{2}/, '~\1~')
      .gsub(/(?<!`)`((?!\s)([^`*]+?)(?<!\s))`(?!`)/, '```\1```')
  end

  # WhatsApp formatting → Chatwoot markdown (mirrors Evolution chatwoot.service.ts inbound).
  def inbound(text)
    return text if text.blank?

    text
      .gsub(/\*((?!\s)([^\n*]+?)(?<!\s))\*/, '**\1**')
      .gsub(/_((?!\s)([^\n_]+?)(?<!\s))_/, '*\1*')
      .gsub(/~((?!\s)([^\n~]+?)(?<!\s))~/, '~~\1~~')
  end
end
