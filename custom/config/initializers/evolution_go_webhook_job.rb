# frozen_string_literal: true

# FORK: ensure Evolution Go WhatsappEventsJob prepend loads in all environments
# (development runs with eager_load=false — without this, inbound Go webhooks
# fall through to the base job and are dropped).
Rails.application.config.to_prepare do
  path = Rails.root.join('custom/app/jobs/custom/webhooks/whatsapp_events_job_evolution_go.rb')
  require path.to_s if path.exist?
end
