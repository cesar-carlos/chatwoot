# frozen_string_literal: true

RSpec.configure do |config|
  config.after do
    Redis::Alfred.scan_each(match: format(Redis::RedisKeys::MESSAGE_SOURCE_KEY, id: '*')) do |key|
      Redis::Alfred.delete(key)
    end
  end
end
