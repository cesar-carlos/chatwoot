# frozen_string_literal: true

# Smoke test for audio transcription fork components.
# Run without a real Groq API key:
#   bundle exec rails runner doc/scripts/smoke-test-audio-transcription.rb
#
# Optional dry-run mode (default): stubs Groq provider and skips external calls.

dry_run = !ENV['SMOKE_TEST_LIVE']

puts '=== Audio Transcription Smoke Test ==='
puts "Mode: #{dry_run ? 'dry-run (stubbed)' : 'live'}"

account = Account.first
user = User.first
attachment = Attachment.where(file_type: :audio).first

unless account && user
  puts '❌ Missing account or user seed data'
  exit 1
end

puts "\n1. Mutual exclusion check"
automatic_enabled = ActiveModel::Type::Boolean.new.cast(account.audio_transcriptions)
manual_allowed = user.groq_token.present? && !automatic_enabled
puts "   account.audio_transcriptions=#{automatic_enabled}"
puts "   user.has_groq_token=#{user.groq_token.present?}"
puts "   manual Groq allowed=#{manual_allowed}"

puts "\n2. Metadata reader"
if attachment
  text = Custom::TranscriptionMetadata.read_text(attachment)
  state = Custom::TranscriptionMetadata.read_state(attachment)
  puts "   attachment_id=#{attachment.id} state=#{state.inspect} text_length=#{text.length}"
else
  puts '   skipped (no audio attachment found)'
end

puts "\n3. Provider dry-run"
if dry_run
  provider = Custom::Transcription::GroqProvider.new(user: user, params: {})

  if attachment
    stubbed_result = {
      text: 'smoke-test transcript',
      state: 'success',
      provider: 'groq',
      model: Custom::Groq::AudioTranscriptionService::DEFAULT_MODEL,
      transcribed_at: Time.current.to_i,
      metadata: {}
    }
    provider.define_singleton_method(:transcribe) { |_attachment, _options = {}| stubbed_result }
    result = provider.transcribe(attachment)
    puts "   provider returned state=#{result[:state]} text=#{result[:text]}"
  else
    puts '   skipped (no audio attachment found)'
  end
else
  puts '   live mode requested — set SMOKE_TEST_LIVE=1 only when Groq token is configured'
end

puts "\n4. Rate limiter"
limiter = Custom::Transcription::RateLimiter.new(user_id: user.id)
within = limiter.within_limit?
puts "   within_limit?=#{within}"

puts "\n✅ Smoke test completed"
