# frozen_string_literal: true

class Custom::Whatsapp::EvolutionGo::WebhookTestService
  pattr_initialize [:channel!]

  def perform
    enqueued_at = Time.current.iso8601
    Webhooks::WhatsappEventsJob.perform_later(test_payload.merge(enqueued_at: enqueued_at))
    channel.reload
    config = (channel.provider_config || {}).stringify_keys
    merged = config.merge('last_webhook_at' => enqueued_at)
    channel.update_columns(provider_config: merged, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations

    { ok: true, enqueued_at: enqueued_at }
  end

  private

  def test_payload
    config = channel.provider_config || {}
    {
      event: 'MESSAGE',
      evolution_go_instance_name: config['instance_name'],
      channel_id: channel.id,
      data: {
        key: {
          remoteJid: '000000000000@s.whatsapp.net',
          fromMe: false,
          id: "test-webhook-#{SecureRandom.hex(8)}"
        },
        pushName: 'Webhook Test',
        message: { conversation: '[Chatwoot webhook pipeline test — ignored contact]' },
        messageTimestamp: Time.current.to_i
      }
    }
  end
end
