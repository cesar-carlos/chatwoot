require 'rails_helper'

RSpec.describe Enterprise::Concerns::Attachment, type: :model do
  let(:account) { create(:account, audio_transcriptions: true) }
  let(:conversation) { create(:conversation, account: account) }
  let(:message) { create(:message, conversation: conversation, account: account) }

  describe 'after_create_commit :enqueue_audio_transcription' do
    it 'does not enqueue automatic transcription for audio attachments' do
      expect do
        message.attachments.create!(
          account: account,
          file_type: :audio,
          file: fixture_file_upload('public/audio/widget/ding.mp3')
        )
      end.not_to have_enqueued_job(Messages::AudioTranscriptionJob)
    end
  end
end
