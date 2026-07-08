module Enterprise::Whatsapp::Providers::WhatsappCloudService
  # FORK: delegate Meta Cloud voice API to MetaCloud::Adapter
  def pre_accept_call(call_id, sdp_answer)
    meta_cloud_voice_adapter.pre_accept_call(call_id, sdp_answer)
  end

  def accept_call(call_id, sdp_answer)
    meta_cloud_voice_adapter.accept_call(call_id, sdp_answer)
  end

  def reject_call(call_id)
    meta_cloud_voice_adapter.reject_call(call_id)
  end

  def terminate_call(call_id)
    meta_cloud_voice_adapter.terminate_call(call_id)
  end

  def send_call_permission_request(to_phone_number, body_text = I18n.t('conversations.messages.whatsapp.call_permission_request_body'))
    meta_cloud_voice_adapter.send_call_permission_request(to_phone_number, body_text)
  end

  def initiate_call(to_phone_number, sdp_offer)
    meta_cloud_voice_adapter.initiate_call(to_phone_number, sdp_offer)
  end

  def update_calling_status(status)
    response = HTTParty.post(
      "#{calls_phone_id_path}/settings",
      headers: api_headers,
      body: { calling: { status: status } }.to_json
    )
    return true if response.success?

    parsed = response.parsed_response.is_a?(Hash) ? response.parsed_response : {}
    error = parsed['error'].is_a?(Hash) ? parsed['error'] : {}
    Rails.logger.error "[WHATSAPP CALL] update_calling_status failed: status=#{response.code} body=#{response.body}"
    raise meta_error_message(error, 'Failed to update calling status')
  end

  private

  def calls_phone_id_path
    base = ENV.fetch('WHATSAPP_CLOUD_BASE_URL', 'https://graph.facebook.com')
    version = GlobalConfigService.load('WHATSAPP_API_VERSION', WHATSAPP_CALLING_API_VERSION_FALLBACK)
    "#{base}/#{version}/#{whatsapp_channel.provider_config['phone_number_id']}"
  end

  def call_action_body(call_id, action, sdp_answer = nil)
    body = { messaging_product: 'whatsapp', call_id: call_id, action: action }
    body[:session] = { sdp: sdp_answer, sdp_type: 'answer' } if sdp_answer
    body
  end

  def call_api(action_name, body)
    url = "#{calls_phone_id_path}/calls"
    Rails.logger.info "[WHATSAPP CALL] #{action_name} POST #{url} body=#{body.except(:session).to_json}"
    response = HTTParty.post(url, headers: api_headers, body: body.to_json)
    Rails.logger.error "[WHATSAPP CALL] #{action_name} failed: status=#{response.code} body=#{response.body}" unless response.success?
    response.success?
  end

  def permission_request_body(to_phone_number, body_text)
    {
      messaging_product: 'whatsapp', recipient_type: 'individual', to: to_phone_number,
      type: 'interactive',
      interactive: {
        type: 'call_permission_request',
        action: { name: 'call_permission_request' },
        body: { text: body_text }
      }
    }.to_json
  end

  def initiate_call_body(to_phone_number, sdp_offer)
    {
      messaging_product: 'whatsapp', to: to_phone_number, action: 'connect',
      session: { sdp: sdp_offer, sdp_type: 'offer' }
    }.to_json
  end

  def process_initiate_call_response(response)
    return response.parsed_response if response.success?

    Rails.logger.error "[WHATSAPP CALL] initiate_call failed: status=#{response.code} body=#{response.body}"
    parsed = response.parsed_response.is_a?(Hash) ? response.parsed_response : {}
    error = parsed['error'].is_a?(Hash) ? parsed['error'] : {}
    error_code = error['code']
    error_msg = meta_error_message(error, 'Failed to initiate call')

    raise Voice::CallErrors::NoCallPermission, error_msg if error_code == Voice::CallErrors::NO_CALL_PERMISSION_CODE

    raise Voice::CallErrors::CallFailed, error_msg
  end

  # Meta often returns a blank error_user_msg (e.g. code 131044 business-eligibility);
  # an empty string is truthy, so `||` would surface it. Prefer the first non-blank field.
  def meta_error_message(error, default)
    error['error_user_msg'].presence || error['message'].presence || error['error_user_title'].presence || default
  end
end
