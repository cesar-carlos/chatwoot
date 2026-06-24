class Api::V1::Accounts::WhatsappCallsController < Api::V1::Accounts::BaseController
  before_action :set_call, only: %i[show accept reject terminate upload_recording]
  before_action :set_conversation, only: :initiate
  before_action :ensure_calling_enabled, only: :initiate
  before_action :ensure_sdp_offer, only: :initiate
  before_action :ensure_contact_phone, only: :initiate
  before_action :ensure_recording_present, only: :upload_recording
  before_action :ensure_call_message, only: :upload_recording

  rescue_from Voice::CallErrors::NotRinging,
              Voice::CallErrors::AlreadyAccepted,
              Voice::CallErrors::CallFailed,
              with: :render_call_error
  rescue_from Voice::CallErrors::NoCallPermission, with: :handle_no_call_permission

  def show; end

  def accept
    call_service.accept
  end

  def reject
    call_service.reject
  end

  def terminate
    call_service.terminate
  end

  def upload_recording
    @upload_status = @call.message.with_lock { attach_recording_idempotently }
  end

  def initiate
    @call = Voice::OutboundWhatsappCallBuilder.perform!(
      conversation: @conversation,
      agent: Current.user,
      sdp_offer: params[:sdp_offer],
      provider_service: provider_service
    )
    @message = @call.message
  end

  private

  def call_service
    @call_service ||= Whatsapp::CallService.new(call: @call, agent: Current.user, sdp_answer: params[:sdp_answer])
  end

  def provider_service
    @provider_service ||= @conversation.inbox.channel.provider_service
  end

  def set_call
    @call = Current.account.calls.whatsapp.find(params[:id])
    authorize @call.conversation, :show?
  end

  def set_conversation
    @conversation = Current.account.conversations.find_by!(display_id: params[:conversation_id])
    authorize @conversation, :show?
  end

  def ensure_calling_enabled
    channel = @conversation.inbox.channel
    return if channel.is_a?(Channel::Whatsapp) && channel.voice_enabled?

    render_could_not_create_error(I18n.t('errors.whatsapp.calls.not_enabled'))
  end

  def ensure_sdp_offer
    return if params[:sdp_offer].present?

    render_could_not_create_error(I18n.t('errors.whatsapp.calls.sdp_offer_required'))
  end

  def ensure_contact_phone
    return if @conversation.contact&.phone_number.present?

    render_could_not_create_error(I18n.t('errors.whatsapp.calls.contact_phone_required'))
  end

  def ensure_recording_present
    return if params[:recording].present?

    render_could_not_create_error(I18n.t('errors.whatsapp.calls.no_recording'))
  end

  def ensure_call_message
    return if @call.message.present?

    render_could_not_create_error(I18n.t('errors.whatsapp.calls.no_message'))
  end

  def attach_recording_idempotently
    return 'already_uploaded' if @call.message.attachments.exists?(file_type: :audio)

    @call.message.attachments.create!(account_id: @call.account_id, file_type: :audio, file: params[:recording])
    'uploaded'
  end

  # Meta error 138006 means the contact hasn't opted in yet; delegate opt-in
  # flow to the dedicated service (throttle, template, activity, WAMID record).
  # 422 (not 200) so clients treating 2xx as "call placed" can't mistake the
  # permission-template path for a successful dial.
  def handle_no_call_permission
    status = Whatsapp::CallPermissionRequestService.new(
      conversation: @conversation, agent: Current.user
    ).perform

    return render_could_not_create_error(I18n.t('errors.whatsapp.calls.permission_request_failed')) if status == :failed

    render json: { status: status }, status: :unprocessable_entity
  end

  def render_call_error(error)
    render_could_not_create_error(error.message)
  end
end
