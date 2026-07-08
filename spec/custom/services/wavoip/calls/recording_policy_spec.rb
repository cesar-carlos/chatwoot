# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Wavoip::Calls::RecordingPolicy do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_wavoip, account: account) }
  let(:inbox) { channel.inbox }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:record_url) { 'https://example.com/recording.ogg' }
  let!(:call) do
    create(
      :call,
      account: account,
      inbox: inbox,
      conversation: conversation,
      contact: conversation.contact,
      provider: :wavoip,
      direction: :outgoing,
      status: 'completed',
      provider_call_id: 'policy_call_001'
    )
  end

  before do
    account.enable_features!('channel_voice', 'channel_wavoip')
  end

  def policy(record_status: nil, record_url: self.record_url, call: nil)
    described_class.new(inbox: inbox, record_url: record_url, record_status: record_status, call: call)
  end

  describe '.recording_feature_enabled?' do
    it 'is true when call_recording_enabled is not false' do
      expect(described_class.recording_feature_enabled?(inbox: inbox)).to be(true)
    end

    it 'is false when call_recording_enabled is false' do
      channel.update!(provider_config: channel.provider_config.merge('call_recording_enabled' => false))

      expect(described_class.recording_feature_enabled?(inbox: inbox)).to be(false)
    end
  end

  describe '#attachable?' do
    it 'allows READY recordings with a URL' do
      expect(policy(record_status: 'READY').attachable?).to be(true)
    end

    it 'allows recordings when record_status is absent' do
      expect(policy(record_status: nil).attachable?).to be(true)
    end

    it 'rejects DISABLED status' do
      expect(policy(record_status: 'DISABLED').attachable?).to be(false)
    end

    it 'rejects EMPTY_RECORDING status' do
      expect(policy(record_status: 'EMPTY_RECORDING').attachable?).to be(false)
    end

    it 'rejects RECORDING status' do
      expect(policy(record_status: 'RECORDING').attachable?).to be(false)
    end

    it 'rejects MIXING status' do
      expect(policy(record_status: 'MIXING').attachable?).to be(false)
    end

    it 'rejects when inbox recording is disabled' do
      channel.update!(provider_config: channel.provider_config.merge('call_recording_enabled' => false))

      expect(policy(record_status: 'READY').attachable?).to be(false)
    end

    it 'rejects blank record_url' do
      expect(policy(record_url: nil).attachable?).to be(false)
    end

    it 'rejects when call is not completed' do
      call.update!(status: 'in_progress')

      expect(policy(record_status: 'READY', call: call).attachable?).to be(false)
    end

    it 'logs unknown record_status values' do
      allow(Rails.logger).to receive(:warn)

      expect(policy(record_status: 'PROCESSING', call: call).attachable?).to be(false)
      expect(Rails.logger).to have_received(:warn).with(/Unknown record_status=PROCESSING/)
    end
  end

  describe '#persist_status_only?' do
    it 'is true for RECORDING status' do
      expect(policy(record_status: 'RECORDING').persist_status_only?).to be(true)
    end

    it 'is false for READY status' do
      expect(policy(record_status: 'READY').persist_status_only?).to be(false)
    end
  end
end
