class Custom::Transcription::RateLimiter
  DEFAULT_LIMIT = 10
  PERIOD = 1.minute

  def initialize(user_id:)
    @user_id = user_id
  end

  def within_limit?
    key = "audio_transcription:user:#{@user_id}"
    count = Redis::Alfred.get(key).to_i

    return false if count >= limit

    Redis::Alfred.incr(key)
    Redis::Alfred.expire(key, PERIOD.to_i) if count.zero?
    true
  end

  private

  def limit
    ENV.fetch('RATE_LIMIT_AUDIO_TRANSCRIPTION', DEFAULT_LIMIT.to_s).to_i
  end
end
