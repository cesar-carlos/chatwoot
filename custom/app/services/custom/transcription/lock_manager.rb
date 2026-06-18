class Custom::Transcription::LockManager
  LOCK_TTL = 120.seconds

  def initialize(attachment_id:)
    @attachment_id = attachment_id
  end

  def lock_key
    "audio_transcription:attachment:#{@attachment_id}"
  end

  def acquire
    redis_lock_manager.lock(lock_key, LOCK_TTL)
  end

  def release
    redis_lock_manager.unlock(lock_key)
  end

  def locked?
    redis_lock_manager.locked?(lock_key)
  end

  private

  def redis_lock_manager
    @redis_lock_manager ||= Redis::LockManager.new
  end
end
