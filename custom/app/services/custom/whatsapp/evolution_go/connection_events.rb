# frozen_string_literal: true

class Custom::Whatsapp::EvolutionGo::ConnectionEvents
  pattr_initialize [:channel!, :connection_service!]

  def handle_event(envelope)
    envelope = envelope.with_indifferent_access
    case envelope[:event].to_s.upcase
    when 'CONNECTION', 'CONNECTED', 'DISCONNECTED', 'LOGGEDOUT', 'LOGGED_OUT'
      handle_connection_event(envelope)
    when 'QRCODE', 'QR_CODE'
      handle_qrcode_event(envelope)
    end
  end

  def qrcode_storage_attrs(data)
    return {} unless data.is_a?(Hash)

    data = data.with_indifferent_access
    qrcode_field = dig_field(data, 'qrcode', 'Qrcode')
    attrs = {}
    base64 = qrcode_base64_value(data, qrcode_field)
    code = qrcode_code_value(data, qrcode_field)
    attrs['last_qr_base64'] = base64 if base64.present?
    attrs['last_qr_code'] = code if code.present?
    attrs
  end

  private

  def qrcode_base64_value(data, qrcode_field)
    if qrcode_field.is_a?(Hash)
      dig_field(qrcode_field, 'qrcode', 'Qrcode', 'base64', 'Base64')
    elsif qrcode_field.is_a?(String)
      qrcode_field.split('|', 2).first
    elsif data['qrcode'].is_a?(String)
      data['qrcode'].split('|', 2).first
    end
  end

  def qrcode_code_value(data, qrcode_field)
    code = dig_field(data, 'code', 'Code')
    return code if code.present?
    return dig_field(qrcode_field, 'code', 'Code') if qrcode_field.is_a?(Hash)

    qrcode_field.to_s.split('|', 2)[1].presence if qrcode_field.is_a?(String)
  end

  def handle_connection_event(envelope)
    data = envelope[:data]
    state = map_connection_state(data, event: envelope[:event])
    return if state.blank?

    previous_status = provider_config['connection_status']
    connection_service.update_connection_status(state)
    jid = dig_field(data.with_indifferent_access, 'jid', 'Jid', 'JID') if data.is_a?(Hash)
    connection_service.sync_phone_from_jid!(jid) if state == 'open' && jid.present?
    connection_service.sync_phone_number! if state == 'open'
    broadcast({ connection_status: state, phone_number: channel.phone_number }.compact)
    notify_disconnection!(previous_status, state)
  end

  def provider_config
    channel.provider_config || {}
  end

  def handle_qrcode_event(envelope)
    attrs = qrcode_storage_attrs(envelope[:data])
    return if attrs.blank?

    attrs['connection_status'] = 'connecting'
    connection_service.update_runtime_config!(attrs)
    broadcast(
      {
        connection_status: 'connecting',
        qrcode_base64: attrs['last_qr_base64'],
        qrcode_code: attrs['last_qr_code']
      }.compact
    )
  end

  def map_connection_state(data, event: nil) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    event_state = state_from_event_name(event)
    return event_state if event_state.present?

    return if data.blank?

    data = data.with_indifferent_access if data.is_a?(Hash)
    explicit = dig_field(data, 'state', 'State', 'connectionState', 'status', 'Status')
    return normalize_state(explicit) if explicit.present?

    connected = ActiveModel::Type::Boolean.new.cast(dig_field(data, 'connected', 'Connected'))
    logged_in = ActiveModel::Type::Boolean.new.cast(dig_field(data, 'loggedIn', 'LoggedIn'))
    return 'open' if connected && logged_in
    return 'connecting' if connected

    reason = dig_field(data, 'reason', 'Reason')
    return 'close' if reason.present? && !connected

    'close'
  end

  def state_from_event_name(event)
    case event.to_s.upcase
    when 'CONNECTED' then 'open'
    when 'DISCONNECTED', 'LOGGEDOUT', 'LOGGED_OUT' then 'close'
    end
  end

  def normalize_state(value)
    case value.to_s.downcase
    when 'open', 'connected' then 'open'
    when 'connecting' then 'connecting'
    else 'close'
    end
  end

  def dig_field(hash, *keys)
    Custom::Whatsapp::EvolutionGo::FieldDig.dig_field(hash, *keys)
  end

  def broadcast(payload)
    connection_service.broadcast_connection_event(payload)
  end

  def notify_disconnection!(previous_status, state)
    return unless state == 'close' && previous_status != 'close'

    inbox = channel.inbox
    return if inbox.blank?

    Custom::Whatsapp::EvolutionGo::Broadcaster.new(inbox: inbox).broadcast_disconnected
  end
end
