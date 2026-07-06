# frozen_string_literal: true

class Custom::Whatsapp::EvolutionGo::ConnectionEvents
  pattr_initialize [:channel!, :connection_service!]

  def handle_event(envelope)
    envelope = envelope.with_indifferent_access
    case envelope[:event]
    when 'CONNECTION'
      handle_connection_event(envelope)
    when 'QRCODE'
      handle_qrcode_event(envelope)
    end
  end

  def qrcode_storage_attrs(data)
    return {} unless data.is_a?(Hash)

    data = data.with_indifferent_access
    qrcode = dig_field(data, 'qrcode', 'Qrcode') || data
    attrs = {}
    base64 = qrcode_base64_value(data, qrcode)
    code = qrcode_code_value(data, qrcode)
    attrs['last_qr_base64'] = base64 if base64.present?
    attrs['last_qr_code'] = code if code.present?
    attrs
  end

  private

  def qrcode_base64_value(data, qrcode)
    base64 = dig_field(qrcode, 'qrcode', 'Qrcode', 'base64', 'Base64') || qrcode if qrcode.is_a?(Hash)
    base64 || (data['qrcode'] if data['qrcode'].is_a?(String))
  end

  def qrcode_code_value(data, qrcode)
    dig_field(data, 'code', 'Code') || (dig_field(qrcode, 'code', 'Code') if qrcode.is_a?(Hash))
  end

  def provider_config
    channel.provider_config || {}
  end

  def handle_connection_event(envelope)
    state = map_connection_state(envelope[:data])
    return if state.blank?

    connection_service.update_connection_status(state)
    connection_service.sync_phone_number! if state == 'open'
    broadcast({ connection_status: state, phone_number: channel.phone_number }.compact)
  end

  def handle_qrcode_event(envelope)
    attrs = qrcode_storage_attrs(envelope[:data])
    return if attrs.blank?

    connection_service.update_runtime_config!(attrs)
    broadcast(
      {
        qrcode_base64: attrs['last_qr_base64'],
        qrcode_code: attrs['last_qr_code']
      }.compact
    )
  end

  def map_connection_state(data)
    return if data.blank?

    data = data.with_indifferent_access if data.is_a?(Hash)
    explicit = dig_field(data, 'state', 'State', 'connectionState')
    return normalize_state(explicit) if explicit.present?

    connected = ActiveModel::Type::Boolean.new.cast(dig_field(data, 'connected', 'Connected'))
    logged_in = ActiveModel::Type::Boolean.new.cast(dig_field(data, 'loggedIn', 'LoggedIn'))
    return 'open' if connected && logged_in
    return 'connecting' if connected

    'close'
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
end
