# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Whatsapp::EvolutionGo::InteractivePayload do
  def message_with(content_type, items)
    instance_double(
      Message,
      content_type: content_type,
      content_attributes: { 'items' => items }
    )
  end

  describe '.carousel' do
    it 'rejects a card without media' do
      message = message_with(
        'cards',
        [{ 'title' => 'Offer', 'description' => 'Today', 'actions' => [{ 'type' => 'postback', 'text' => 'Ok', 'payload' => '1' }] }]
      )

      result = described_class.carousel(message)

      expect(result.success?).to be(false)
      expect(result.error).to eq(described_class::MISSING_MEDIA)
    end

    it 'truncates a carousel button label to the reply-button limit' do
      message = message_with(
        'cards',
        [{
          'title' => 'Offer',
          'description' => 'Today',
          'media_url' => 'https://cdn.example/a.png',
          'actions' => [{ 'type' => 'postback', 'text' => 'A' * 30, 'payload' => 'buy' }]
        }]
      )

      result = described_class.carousel(message)

      expect(result.payload[:cards].first[:buttons].first[:displayText]).to eq(('A' * 30).truncate(20))
    end
  end

  describe '.links' do
    it 'rejects an article item without a link' do
      message = message_with('article', [{ 'title' => 'Docs', 'description' => 'Reference' }])

      result = described_class.links(message)

      expect(result.error).to eq(described_class::MISSING_LINK)
    end
  end
end
