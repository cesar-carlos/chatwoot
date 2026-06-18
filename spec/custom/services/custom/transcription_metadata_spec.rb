require 'rails_helper'

RSpec.describe Custom::TranscriptionMetadata do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:message) { create(:message, conversation: conversation) }
  let(:attachment) { message.attachments.create!(account: account, file_type: :audio) }

  describe '.read_started_at' do
    it 'returns started_at from transcription metadata' do
      attachment.update!(meta: { 'transcription' => { 'started_at' => 1_700_000_000 } })

      expect(described_class.read_started_at(attachment)).to eq(1_700_000_000)
    end

    it 'falls back to transcribed_at' do
      attachment.update!(meta: { 'transcription' => { 'transcribed_at' => 1_700_000_100 } })

      expect(described_class.read_started_at(attachment)).to eq(1_700_000_100)
    end
  end

  describe '.stale_processing?' do
    it 'returns true when processing started_at is older than TTL' do
      stale_time = (Custom::TranscriptionMetadata::PROCESSING_STALE_TTL + 10.seconds).ago.to_i
      attachment.update!(meta: { 'transcription' => { 'state' => 'processing', 'started_at' => stale_time } })

      expect(described_class.stale_processing?(attachment)).to be(true)
    end

    it 'returns false when processing started_at is recent' do
      attachment.update!(meta: { 'transcription' => { 'state' => 'processing', 'started_at' => Time.current.to_i } })

      expect(described_class.stale_processing?(attachment)).to be(false)
    end

    it 'returns true when processing has no started_at' do
      attachment.update!(meta: { 'transcription' => { 'state' => 'processing' } })

      expect(described_class.stale_processing?(attachment)).to be(true)
    end
  end

  describe '.actively_processing?' do
    let(:lock_manager) { instance_double(Custom::Transcription::LockManager, locked?: true) }

    it 'returns true for recent processing with lock held' do
      attachment.update!(meta: { 'transcription' => { 'state' => 'processing', 'started_at' => Time.current.to_i } })

      expect(
        described_class.actively_processing?(attachment, lock_manager: lock_manager, force_refresh: false)
      ).to be(true)
    end

    it 'returns false when force_refresh is true' do
      attachment.update!(meta: { 'transcription' => { 'state' => 'processing', 'started_at' => Time.current.to_i } })

      expect(
        described_class.actively_processing?(attachment, lock_manager: lock_manager, force_refresh: true)
      ).to be(false)
    end

    it 'returns false for stale processing even when lock is held' do
      stale_time = (Custom::TranscriptionMetadata::PROCESSING_STALE_TTL + 10.seconds).ago.to_i
      attachment.update!(meta: { 'transcription' => { 'state' => 'processing', 'started_at' => stale_time } })

      expect(
        described_class.actively_processing?(attachment, lock_manager: lock_manager, force_refresh: false)
      ).to be(false)
    end
  end

  describe '.clear_processing_state!' do
    it 'removes processing transcription metadata' do
      attachment.update!(meta: { 'transcription' => { 'state' => 'processing', 'started_at' => 1 } })

      described_class.clear_processing_state!(attachment)

      expect(attachment.reload.meta).not_to have_key('transcription')
    end

    it 'removes error transcription metadata' do
      attachment.update!(meta: { 'transcription' => { 'state' => 'error', 'error' => 'failed' } })

      described_class.clear_processing_state!(attachment)

      expect(attachment.reload.meta).not_to have_key('transcription')
    end
  end
end
