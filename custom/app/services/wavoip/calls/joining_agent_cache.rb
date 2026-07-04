# frozen_string_literal: true

module Wavoip::Calls::JoiningAgentCache
  KEY_PREFIX = 'wavoip:joining_agent'
  TTL = 5.minutes

  module_function

  def write(call_id, user_id)
    Rails.cache.write(cache_key(call_id), user_id, expires_in: TTL)
  end

  def read(call_id)
    Rails.cache.read(cache_key(call_id))
  end

  def delete(call_id)
    Rails.cache.delete(cache_key(call_id))
  end

  def cache_key(call_id)
    "#{KEY_PREFIX}:#{call_id}"
  end
end
