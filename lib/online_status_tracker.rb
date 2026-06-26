class OnlineStatusTracker
  # NOTE: You can customise the environment variable to keep your agents/contacts as online for longer
  PRESENCE_DURATION = ENV.fetch('PRESENCE_DURATION', 20).to_i.seconds
  # Widget pings every 60s, so contacts need a longer presence window
  CONTACT_PRESENCE_DURATION = ENV.fetch('CONTACT_PRESENCE_DURATION', 90).to_i.seconds

  # presence : sorted set with timestamp as the score & object id as value

  # obj_type: Contact | User
  def self.update_presence(account_id, obj_type, obj_id)
    ::Redis::Alfred.zadd(presence_key(account_id, obj_type), Time.now.to_i, obj_id)
  end

  def self.get_presence(account_id, obj_type, obj_id)
    connected_time = ::Redis::Alfred.zscore(presence_key(account_id, obj_type), obj_id)
    duration = obj_type == 'Contact' ? CONTACT_PRESENCE_DURATION : PRESENCE_DURATION
    connected_time && connected_time > (Time.zone.now - duration).to_i
  end

  def self.presence_key(account_id, type)
    case type
    when 'Contact'
      format(::Redis::Alfred::ONLINE_PRESENCE_CONTACTS, account_id: account_id)
    else
      format(::Redis::Alfred::ONLINE_PRESENCE_USERS, account_id: account_id)
    end
  end

  # online status : online | busy | offline
  # redis hash with obj_id key && status as value

  def self.set_status(account_id, user_id, status)
    ::Redis::Alfred.hset(status_key(account_id), user_id, status)
  end

  def self.get_status(account_id, user_id)
    ::Redis::Alfred.hget(status_key(account_id), user_id)
  end

  def self.status_key(account_id)
    format(::Redis::Alfred::ONLINE_STATUS, account_id: account_id)
  end

  def self.get_available_contact_ids(account_id)
    range_start = (Time.zone.now - CONTACT_PRESENCE_DURATION).to_i
    # exclusive minimum score is specified by prefixing (
    # we are clearing old records because this could clogg up the sorted set
    ::Redis::Alfred.zremrangebyscore(presence_key(account_id, 'Contact'), '-inf', "(#{range_start}")
    ::Redis::Alfred.zrangebyscore(presence_key(account_id, 'Contact'), range_start, '+inf')
  end

  def self.get_available_contacts(account_id)
    # returns {id1: 'online', id2: 'online'}
    get_available_contact_ids(account_id).index_with { |_id| 'online' }
  end

  def self.get_available_users(account_id)
    user_ids = get_available_user_ids(account_id)

    return {} if user_ids.blank?

    user_availabilities = ::Redis::Alfred.hmget(status_key(account_id), user_ids)
    user_ids.map.with_index { |id, index| [id, (user_availabilities[index] || get_availability_from_db(account_id, id))] }.to_h
  end

  # Returns { user_id => status } for the given user_ids that are present and match status.
  def self.get_users_with_status(account_id, user_ids:, status:)
    return {} if user_ids.blank?

    candidate_ids = present_candidate_user_ids(account_id, user_ids)
    return {} if candidate_ids.blank?

    build_status_map(account_id, candidate_ids, status)
  end

  def self.present_candidate_user_ids(account_id, user_ids)
    normalized_ids = user_ids.map(&:to_i).uniq
    return [] if normalized_ids.blank?

    always_on_ids = always_present_user_ids(account_id, normalized_ids)
    normalized_ids.select do |user_id|
      always_on_ids.include?(user_id) || get_presence(account_id, 'User', user_id)
    end
  end
  private_class_method :present_candidate_user_ids

  def self.always_present_user_ids(account_id, user_ids)
    Account.find(account_id).account_users
           .where(user_id: user_ids, auto_offline: false)
           .pluck(:user_id)
  end
  private_class_method :always_present_user_ids

  def self.build_status_map(account_id, candidate_ids, status)
    ids = candidate_ids.map(&:to_s)
    statuses = ::Redis::Alfred.hmget(status_key(account_id), ids)
    ids.each_with_index.with_object({}) do |(id, index), result|
      availability = statuses[index] || get_availability_from_db(account_id, id)
      result[id] = availability if availability == status
    end
  end
  private_class_method :build_status_map

  def self.get_availability_from_db(account_id, user_id)
    availability = Account.find(account_id).account_users.find_by(user_id: user_id).availability
    set_status(account_id, user_id, availability)
    availability
  end

  def self.get_available_user_ids(account_id)
    account = Account.find(account_id)
    range_start = (Time.zone.now - PRESENCE_DURATION).to_i
    user_ids = ::Redis::Alfred.zrangebyscore(presence_key(account_id, 'User'), range_start, '+inf')
    # since we are dealing with redis items as string, casting to string
    user_ids += account.account_users.where(auto_offline: false)&.map(&:user_id)&.map(&:to_s)
    user_ids.uniq
  end
end
