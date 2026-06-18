require 'rails_helper'

RSpec.describe Api::V1::Accounts::TranscriptionsController, type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, groq_token: "gsk_#{'a' * 40}") }
  let(:conversation) { create(:conversation, account: account) }
  let(:message) { create(:message, conversation: conversation) }
  let(:attachment) { message.attachments.create!(account: account, file_type: :audio) }
  let(:headers) { user.create_new_auth_token }
  let(:endpoint) { "/api/v1/accounts/#{account.id}/transcriptions" }
  let(:transcription_result) do
    {
      text: 'Hello world transcription',
      state: 'success',
      provider: 'groq',
      model: 'whisper-large-v3-turbo',
      transcribed_at: Time.current.to_i,
      metadata: { language: 'en', duration: 1.2 }
    }
  end
  let(:provider_double) { instance_double(Custom::Transcription::GroqProvider, transcribe: transcription_result) }
  let(:lock_manager_double) { instance_double(Custom::Transcription::LockManager, acquire: true, release: true, locked?: false) }

  before do
    attachment.file.attach(
      io: File.open(Rails.public_path.join('audio/widget/ding.mp3')),
      filename: 'ding.mp3',
      content_type: 'audio/mpeg'
    )
    allow(provider_double).to receive(:transcribe).and_return(transcription_result)
    allow(Custom::Transcription::GroqProvider).to receive(:new).and_return(provider_double)
    allow(Custom::Transcription::LockManager).to receive(:new).and_return(lock_manager_double)
    allow(Custom::Transcription::RateLimiter).to receive(:new).and_return(
      instance_double(Custom::Transcription::RateLimiter, within_limit?: true)
    )
  end

  describe 'POST /api/v1/accounts/:account_id/transcriptions' do
    context 'when transcription succeeds' do
      it 'returns transcribed text and persists success metadata' do
        post endpoint, params: { attachment_id: attachment.id }, headers: headers, as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body['text']).to eq('Hello world transcription')
        expect(response.parsed_body['state']).to eq('success')
        expect(response.parsed_body['cached']).to be(false)
        expect(attachment.reload.meta.dig('transcription', 'state')).to eq('success')
      end
    end

    context 'when cached transcription exists' do
      before do
        attachment.update!(
          meta: {
            'transcribed_text' => 'Cached transcript',
            'transcription' => {
              'text' => 'Cached transcript',
              'state' => 'success',
              'provider' => 'groq',
              'model' => 'whisper-large-v3-turbo'
            }
          }
        )
      end

      it 'returns cached transcription without calling provider' do
        post endpoint, params: { attachment_id: attachment.id }, headers: headers, as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body['text']).to eq('Cached transcript')
        expect(response.parsed_body['cached']).to be(true)
        expect(provider_double).not_to have_received(:transcribe)
      end
    end

    context 'when groq token is missing' do
      let(:user) { create(:user, account: account, groq_token: nil) }

      it 'returns unprocessable content' do
        post endpoint, params: { attachment_id: attachment.id }, headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body['error_type']).to eq('token_missing')
      end
    end

    context 'when automatic audio transcription is enabled for the account' do
      before { account.update!(audio_transcriptions: true) }

      it 'returns unprocessable content and blocks manual Groq transcription' do
        post endpoint, params: { attachment_id: attachment.id }, headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body['error_type']).to eq('automatic_transcription_enabled')
      end
    end

    context 'when attachment is not found' do
      it 'returns not found' do
        post endpoint, params: { attachment_id: 0 }, headers: headers, as: :json

        expect(response).to have_http_status(:not_found)
        expect(response.parsed_body['error_type']).to eq('attachment_not_found')
      end
    end

    context 'when transcription is already in progress' do
      before do
        allow(lock_manager_double).to receive(:acquire).and_return(false)
        attachment.update!(
          meta: {
            'transcription' => {
              'state' => 'processing',
              'provider' => 'groq'
            }
          }
        )
      end

      it 'returns conflict' do
        post endpoint, params: { attachment_id: attachment.id }, headers: headers, as: :json

        expect(response).to have_http_status(:conflict)
        expect(response.parsed_body['error_type']).to eq('transcription_in_progress')
      end
    end

    context 'when rate limit is exceeded' do
      before do
        allow(Custom::Transcription::RateLimiter).to receive(:new).and_return(
          instance_double(Custom::Transcription::RateLimiter, within_limit?: false)
        )
      end

      it 'returns too many requests' do
        post endpoint, params: { attachment_id: attachment.id }, headers: headers, as: :json

        expect(response).to have_http_status(:too_many_requests)
        expect(response.parsed_body['error_type']).to eq('rate_limit_exceeded')
      end
    end

    context 'when Groq API returns an error' do
      before do
        allow(provider_double).to receive(:transcribe).and_raise(StandardError, 'Invalid API key provided')
      end

      it 'maps the error to unauthorized response' do
        post endpoint, params: { attachment_id: attachment.id }, headers: headers, as: :json

        expect(response).to have_http_status(:unauthorized)
        expect(response.parsed_body['error_type']).to eq('transcription_error')
        expect(response.parsed_body['translation_key']).to eq('AUDIO.API_ERROR.INVALID_KEY')
        expect(attachment.reload.meta.dig('transcription', 'state')).to eq('error')
      end
    end
  end
end
