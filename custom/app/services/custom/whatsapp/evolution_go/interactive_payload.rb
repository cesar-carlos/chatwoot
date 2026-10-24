# frozen_string_literal: true

class Custom::Whatsapp::EvolutionGo::InteractivePayload
  VIDEO_EXTENSIONS = %w[.mp4 .webm .mov].freeze
  BUTTON_LABEL_LIMIT = 20
  REPLY_ACTION = 'postback'
  LINK_ACTION = 'link'
  SUPPORTED_ACTIONS = [REPLY_ACTION, LINK_ACTION].freeze

  MISSING_CARDS = 'Carousel message is missing cards'
  MISSING_MEDIA = 'Carousel card is missing media_url'
  MISSING_DESCRIPTION = 'Carousel card is missing a description'
  MISSING_ACTIONS = 'Carousel card is missing actions'
  MIXED_BUTTONS = 'Carousel card cannot mix reply and link buttons'
  UNSUPPORTED_ACTION = 'Carousel card has an unsupported action'
  MISSING_LINK = 'Article item is missing a link'

  Result = Struct.new(:payload, :error, keyword_init: true) do
    def success?
      error.blank?
    end
  end

  def self.carousel(message)
    new(message).carousel
  end

  def self.links(message)
    new(message).links
  end

  def initialize(message)
    @message = message
  end

  def carousel
    items = content_items
    return failure(MISSING_CARDS) if items.blank?

    cards = []
    items.each do |item|
      card = build_card(item.with_indifferent_access)
      return failure(card) if card.is_a?(String)

      cards << card
    end

    Result.new(payload: { cards: cards })
  end

  def links
    items = content_items
    return failure(MISSING_LINK) if items.blank?

    payloads = []
    items.each do |item|
      link = build_link(item.with_indifferent_access)
      return failure(link) if link.is_a?(String)

      payloads << link
    end

    Result.new(payload: payloads)
  end

  private

  def content_items
    attributes = (@message.content_attributes || {}).with_indifferent_access
    Array.wrap(attributes[:items]).select { |item| item.is_a?(Hash) }
  end

  def build_card(item)
    media_url = item[:media_url].to_s.presence
    return MISSING_MEDIA if media_url.blank?
    return MISSING_DESCRIPTION if item[:description].blank?

    actions = Array.wrap(item[:actions]).select { |action| action.is_a?(Hash) }
    return MISSING_ACTIONS if actions.blank?

    buttons = build_buttons(actions)
    return buttons if buttons.is_a?(String)

    {
      header: card_header(item, media_url),
      body: { text: item[:description].to_s },
      buttons: buttons
    }
  end

  def card_header(item, media_url)
    header = {}
    if video_media?(media_url)
      header[:videoUrl] = media_url
    else
      header[:imageUrl] = media_url
    end
    title = item[:title].to_s.presence
    header[:title] = title if title
    header
  end

  def build_buttons(actions)
    types = actions.map { |action| action.with_indifferent_access[:type].to_s }
    return MIXED_BUTTONS if types.include?(REPLY_ACTION) && types.include?(LINK_ACTION)
    return UNSUPPORTED_ACTION if types.any? { |type| SUPPORTED_ACTIONS.exclude?(type) }

    actions.map { |action| carousel_button(action.with_indifferent_access) }
  end

  def carousel_button(action)
    label = action[:text].to_s.truncate(BUTTON_LABEL_LIMIT)
    if action[:type].to_s == LINK_ACTION
      { type: 'URL', displayText: label, id: action[:uri].to_s }
    else
      { type: 'REPLY', displayText: label, id: action[:payload].to_s }
    end
  end

  def build_link(item)
    url = item[:link].to_s.presence
    return MISSING_LINK if url.blank?

    {
      url: url,
      title: item[:title].to_s.presence,
      description: item[:description].to_s.presence
    }.compact
  end

  def video_media?(url)
    path = URI.parse(url.to_s).path.to_s.downcase
    VIDEO_EXTENSIONS.any? { |extension| path.end_with?(extension) }
  rescue URI::InvalidURIError
    false
  end

  def failure(error)
    Result.new(error: error)
  end
end
