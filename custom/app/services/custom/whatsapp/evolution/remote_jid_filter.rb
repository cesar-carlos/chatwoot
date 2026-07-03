# frozen_string_literal: true

module Custom::Whatsapp::Evolution::RemoteJidFilter
  module_function

  def skip_remote_jid?(remote_jid, config)
    config = (config || {}).stringify_keys
    return true if skip_blank_or_broadcast_jid?(remote_jid, config)
    return true if skip_group_jid?(remote_jid, config)

    ignored_jid_match?(remote_jid, config)
  end

  def skip_blank_or_broadcast_jid?(remote_jid, config)
    remote_jid.blank? ||
      (remote_jid == 'status@broadcast' && config['ignore_status_broadcast'] != false)
  end

  def skip_group_jid?(remote_jid, config)
    remote_jid.end_with?('@g.us') && config['groups_ignore'] != false
  end

  def ignored_jid_match?(remote_jid, config)
    Array(config['ignore_jids']).any? { |pattern| remote_jid.include?(pattern.to_s) }
  end
end
