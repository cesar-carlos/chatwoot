class Api::V1::Accounts::WhatsappCallsController < Api::V1::Accounts::BaseController
  before_action :set_call, only: %i[show accept reject terminate upload_recording]
  before_action :set_call_context, only: :initiate
  before_action :ensure_calling_enabled, only: :initiate
  before_action :ensure_sdp_offer, only: :initiate
  before_action :ensure_contact_phone, only: :initiate
  before_action :ensure_recording_present, only: :upload_recording
  before_action :ensure_call_message, only: :upload_recording

  rescue_from Voice::CallErrors::NotRinging,
              Voice::CallErrors::CallFailed,
              with: :render_call_error
  rescue_from Voice::CallErrors::AlreadyAccepted, with: :render_call_already_accepted
  rescue_from Voice::CallErrors::CallAlreadyEnded, with: :render_call_ended
  rescue_from Voice::CallErrors::NoCallPermission, with: :render_permission_request

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

  # FORK: delegate outbound dial to OutboundWhatsappCallBuilder
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
    @provider_service ||= @inbox.channel.provider_service
  end

  def set_call
    @call = Current.account.calls.whatsapp.find(params[:id])
    authorize @call.conversation, :show?
  end

  def set_call_context
    params[:conversation_id].present? ? set_context_from_conversation : set_context_from_contact
  end

  def set_context_from_conversation
    @conversation = Current.account.conversations.find_by!(display_id: params[:conversation_id])
    authorize @conversation, :show?
    @inbox = @conversation.inbox
    @contact = @conversation.contact
  end

  def set_context_from_contact
    @inbox = Current.account.inboxes.find(params[:inbox_id])
    authorize @inbox, :show?
    @contact = Current.account.contacts.find(params[:contact_id])
    @conversation = conversation_builder.existing_conversation
    # Authorize the thread the call will land in — after the dial is too late to refuse a ringing call.
    authorize(@conversation || conversation_builder.new_conversation, :show?)
  end

  def conversation_builder
    @conversation_builder ||= Whatsapp::CallConversationBuilder.new(inbox: @inbox, contact: @contact, user: Current.user)
  end

  # Created only after the dial succeeds, so a failed call leaves no empty thread and there is nothing to
  # roll back. Re-authorized because a concurrent caller may have created the thread we get back.
  def open_conversation!
    (@conversation || conversation_builder.perform!).tap { |conversation| authorize conversation, :show? }
  end

  def ensure_calling_enabled
    channel = @inbox.channel
    return if channel.is_a?(Channel::Whatsapp) && channel.voice_enabled?

    render_could_not_create_error(I18n.t('errors.whatsapp.calls.not_enabled'))
  end

  def ensure_sdp_offer
    return if params[:sdp_offer].present?

    render_could_not_create_error(I18n.t('errors.whatsapp.calls.sdp_offer_required'))
  end

  def ensure_contact_phone
    return if @contact.phone_number.present?

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

  def render_permission_request
    # Raised mid-dial, so a fresh contact has no thread yet — open one for the opt-in template to land in.
    @conversation = open_conversation!
    status = Whatsapp::CallPermissionRequestService.new(conversation: @conversation).perform

    return render_could_not_create_error(I18n.t('errors.whatsapp.calls.permission_request_failed')) if status == 'failed'

    # 422 (not 200) so any client treating 2xx as "call placed" can't mistake
    # the permission-template path for a successful dial. The FE composable
    # detects this status and surfaces the banner instead of throwing.
    render json: { status: status, conversation_id: @conversation.display_id }, status: :unprocessable_entity
  end

  def render_call_error(error)
    render_could_not_create_error(error.message)
  end

  # 409 (not 422) so the FE can tell "already ended" from a generic failure and dismiss the ringing UI.
  def render_call_ended
    render json: { error: I18n.t('errors.whatsapp.calls.already_ended') }, status: :conflict
  end

  # 409 (not 422) so a losing tab in an accept race dismisses its own ringing UI via the
  # same path as render_call_ended, instead of waiting on the winner's broadcast — which
  # this tab's own optimistic local state can cause it to mistake for its own accept.
  def render_call_already_accepted
    render json: { error: I18n.t('errors.whatsapp.calls.already_accepted') }, status: :conflict
  end
end
