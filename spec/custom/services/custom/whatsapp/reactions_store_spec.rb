# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Whatsapp::ReactionsStore do
  describe '.same_actor?' do
    it 'treats legacy user:<id> entries as the same business actor as user:self' do
      entry = { 'from' => 'user', 'actor_key' => 'user:42', 'actor_id' => 42 }

      expect(
        described_class.same_actor?(
          entry,
          actor_key: described_class::BUSINESS_ACTOR_KEY,
          from: 'user',
          actor_id: 99
        )
      ).to be(true)
    end

    it 'matches contact actors by actor_key' do
      entry = { 'from' => 'contact', 'actor_key' => '5511999999999@s.whatsapp.net' }

      expect(
        described_class.same_actor?(
          entry,
          actor_key: '5511999999999@s.whatsapp.net',
          from: 'contact'
        )
      ).to be(true)
    end
  end

  describe '.business_actor' do
    it 'always uses user:self as actor_key' do
      expect(described_class.business_actor(actor_id: 7)).to eq(
        from: 'user',
        actor_id: 7,
        actor_key: 'user:self'
      )
    end
  end
end
