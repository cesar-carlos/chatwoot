# frozen_string_literal: true

# Wavoip documents a stable direct-download URL for call recordings that
# doesn't depend on receiving the RECORD webhook:
#   https://storage.wavoip.com/{WHATSAPP_CALL_ID}
# https://wavoip.gitbook.io/api/gravacao
#
# Some accounts never receive the RECORD event (webhook not enabled on the
# Wavoip panel side), so we fall back to this URL to still surface the
# recording in the conversation history.
class Wavoip::Calls::DirectRecordingUrl
  BASE_URL = 'https://storage.wavoip.com'

  def self.for(call)
    return if call.provider_call_id.blank?

    "#{BASE_URL}/#{call.provider_call_id}"
  end
end
