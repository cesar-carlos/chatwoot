module Enterprise::Whatsapp::Providers::WhatsappCloudService
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
    meta_cloud_voice_adapter.update_calling_status(status)
  end

  private

  def meta_cloud_voice_adapter
    @meta_cloud_voice_adapter ||= Voice::Provider::MetaCloud::Adapter.new(self)
  end
end
