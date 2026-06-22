# frozen_string_literal: true

class Custom::Whatsapp::Evolution::ConnectionEvents
  pattr_initialize [:channel!, :connection_service!]

  def handle_event(envelope)
    envelope = envelope.with_indifferent_access
    case envelope[:event]
    when 'CONNECTION_UPDATE'
      handle_connection_update_event(envelope)
    when 'QRCODE_UPDATED'
      handle_qrcode_updated_event(envelope)
    end
  end

  def qrcode_storage_attrs(qrcode)
    return {} unless qrcode.is_a?(Hash)

    base64 = qrcode_field(qrcode, :base64)
    code = extract_pairing_code(qrcode)
    attrs = {}
    attrs['last_qr_base64'] = base64 if base64.present?
    attrs['last_qr_code'] = code if code.present?
    attrs
  end

  private

  def provider_config
    channel.provider_config || {}
  end

  def handle_connection_update_event(envelope)
    state = envelope.dig(:data, :state)
    previous_status = provider_config['connection_status']
    connection_service.send(:update_connection_status, state)
    connection_service.send(:extract_phone_number, envelope)
    broadcast_connection_event(connection_event_payload(state))
    notify_disconnection!(previous_status, state)
  end

  def connection_event_payload(state)
    payload = { connection_status: state }
    payload[:phone_number] = channel.phone_number if state == 'open' && channel.phone_number.present?
    payload
  end

  def handle_qrcode_updated_event(envelope)
    qrcode = envelope[:data]
    attrs = qrcode_storage_attrs(qrcode)
    return if attrs.blank?

    connection_service.send(:update_provider_config!, attrs)
    broadcast_connection_event(qrcode_broadcast_payload(attrs))
  end

  def qrcode_broadcast_payload(attrs)
    payload = {}
    payload[:qrcode_base64] = attrs['last_qr_base64'] if attrs['last_qr_base64'].present?
    payload[:qrcode_code] = attrs['last_qr_code'] if attrs['last_qr_code'].present?
    payload
  end

  def extract_pairing_code(qrcode)
    [qrcode_field(qrcode, :pairingCode), qrcode_field(qrcode, :code)].find do |value|
      pairing_code?(value)
    end
  end

  def pairing_code?(value)
    value.present? && value.to_s.gsub(/\W/, '').length == 8
  end

  def qrcode_field(qrcode, field)
    data = qrcode.with_indifferent_access
    nested = data[:qrcode]
    nested = nested.with_indifferent_access if nested.is_a?(Hash)

    nested&.[](field) || data[field]
  end

  def notify_disconnection!(previous_status, state)
    return unless state == 'close' && previous_status != 'close'

    inbox = channel.inbox
    return if inbox.blank?

    Custom::Whatsapp::Evolution::Broadcaster.new(inbox: inbox).broadcast_disconnected
  end

  def broadcast_connection_event(payload)
    inbox = channel.inbox
    return if inbox.blank?

    ActionCable.server.broadcast(
      "evolution:connection:#{inbox.id}",
      payload.merge(inbox_id: inbox.id)
    )
  end
end
