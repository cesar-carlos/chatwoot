# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Wavoip::Calls::OutboundVolumeGuard do
  let(:account_id) { 42 }
  let(:redis_key) { "WAVOIP::OUTBOUND_VOLUME::#{account_id}::#{Time.now.utc.to_date.iso8601}" }

  before do
    Redis::Alfred.delete(redis_key)
  end

  after do
    Redis::Alfred.delete(redis_key)
  end

  describe '.increment_and_warn_level' do
    it 'returns :none below the soft threshold' do
      expect(described_class.increment_and_warn_level(account_id)).to eq(:none)
      expect(Redis::Alfred.get(redis_key)).to eq('1')
    end

    it 'returns :soft when count reaches the soft threshold' do
      Redis::Alfred.set(redis_key, described_class::SOFT_THRESHOLD - 1)

      expect(Rails.logger).to receive(:warn).with(
        /outbound volume account_id=#{account_id} count=#{described_class::SOFT_THRESHOLD} level=soft/
      )

      expect(described_class.increment_and_warn_level(account_id)).to eq(:soft)
    end

    it 'returns :elevated when count reaches the elevated threshold' do
      Redis::Alfred.set(redis_key, described_class::ELEVATED_THRESHOLD - 1)

      expect(Rails.logger).to receive(:warn).with(
        /outbound volume account_id=#{account_id} count=#{described_class::ELEVATED_THRESHOLD} level=elevated/
      )

      expect(described_class.increment_and_warn_level(account_id)).to eq(:elevated)
    end

    it 'sets a TTL on the first increment' do
      described_class.increment_and_warn_level(account_id)

      expect(Redis::Alfred.ttl(redis_key)).to be_within(5).of(described_class::KEY_TTL)
    end
  end
end
