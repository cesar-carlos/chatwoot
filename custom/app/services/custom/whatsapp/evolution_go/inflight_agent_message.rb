# frozen_string_literal: true

# Attaches a WhatsApp echo to the agent message that is still waiting for its
# source_id, instead of inserting a second outgoing row.
class Custom::Whatsapp::EvolutionGo::InflightAgentMessage
  INFLIGHT_WINDOW = 2.minutes

  def self.adopt!(channel:, contact_inbox:, key:, content:)
    new(channel: channel, contact_inbox: contact_inbox, key: key, content: content).adopt!
  end

  def initialize(channel:, contact_inbox:, key:, content:)
    @channel = channel
    @contact_inbox = contact_inbox
    @key = key
    @content = content.to_s.strip
  end

  def adopt!
    chosen = pick_message
    return if chosen.blank?

    stamp!(chosen)
    chosen
  end

  private

  attr_reader :channel, :contact_inbox, :key, :content

  def pick_message
    matched = candidates.select { |message| comparable_bodies(message).include?(content) }
    matched.first if matched.one?
  end

  def candidates
    conversation_ids = channel.inbox.conversations.where(contact_inbox_id: contact_inbox.id).select(:id)
    channel.inbox.messages.outgoing
           .where(private: false, source_id: [nil, ''])
           .where.not(status: :failed)
           .where(conversation_id: conversation_ids)
           .where(created_at: INFLIGHT_WINDOW.ago..)
           .order(created_at: :desc)
           .limit(5)
           .to_a
  end

  def stamp!(message)
    remote_jid = addressing_jid
    attrs = (message.content_attributes || {}).stringify_keys
    jid_key = Custom::Whatsapp::EvolutionGo::ContactEnrichmentService::EVOLUTION_GO_REMOTE_JID_KEY
    attrs[jid_key] = remote_jid if remote_jid.present? && attrs[jid_key].blank?
    message.update!(source_id: key['id'] || key[:id], content_attributes: attrs)
  end

  def addressing_jid
    key_data = key.with_indifferent_access
    resolver = Custom::Whatsapp::EvolutionGo::JidResolver.new(config)
    resolver.addressing_jid(key_data).presence || resolver.resolve_message_jid(key_data)
  end

  def comparable_bodies(message)
    raw_values = [message.content, message.outgoing_content].filter_map { |value| value.to_s.strip.presence }
    bodies = raw_values.flat_map { |value| outbound_variants(message, value) }
    bodies.uniq
  end

  def outbound_variants(message, value)
    variants = [value]
    variants << Custom::Whatsapp::Evolution::MarkdownConverter.outbound(value).to_s.strip if convert_markdown_outbound?
    return variants unless sign_msg?

    sender_name = message.sender&.available_name
    return variants if sender_name.blank?

    variants + variants.map { |body| "#{sender_name}:#{sign_delimiter}#{body}" }
  end

  def config
    channel.provider_config || {}
  end

  def convert_markdown_outbound?
    ActiveModel::Type::Boolean.new.cast(config['convert_markdown_outbound'])
  end

  def sign_msg?
    ActiveModel::Type::Boolean.new.cast(config['sign_msg'])
  end

  def sign_delimiter
    config['sign_delimiter'].presence || "\n"
  end
end
