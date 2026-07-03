# frozen_string_literal: true

module Custom::Whatsapp::Evolution::MessageMutex
  MESSAGE_LOCK_TTL = 30.seconds

  module_function

  def with_lock(channel, sender_id, ttl: MESSAGE_LOCK_TTL)
    return yield if sender_id.blank?

    lock_key = format(
      ::Redis::Alfred::WHATSAPP_MESSAGE_MUTEX,
      inbox_id: channel.inbox.id,
      sender_id: sender_id
    )
    lock_manager = Redis::LockManager.new
    raise MutexApplicationJob::LockAcquisitionError, "Failed to acquire lock for key: #{lock_key}" unless lock_manager.lock(lock_key, ttl)

    begin
      yield
    ensure
      lock_manager.unlock(lock_key)
    end
  end
end
