# frozen_string_literal: true

class Api::V1::Accounts::CallsController < Api::V1::Accounts::BaseController
  before_action :fetch_call

  rescue_from CustomExceptions::CallAlreadyAccepted, with: :render_call_already_accepted

  def join
    authorize @call.inbox, :show?

    return render json: { error: 'Call provider not supported' }, status: :unprocessable_entity unless @call.wavoip?
    return render json: { error: 'Call is not active' }, status: :unprocessable_entity unless @call.ringing? || @call.in_progress?

    record_join_intent!

    head :ok
  end

  def update
    authorize @call.inbox, :show?

    return render json: { error: 'Call provider not supported' }, status: :unprocessable_entity unless @call.wavoip?
    return render json: { error: 'Call is not active' }, status: :unprocessable_entity unless @call.ringing? || @call.in_progress?

    record_agent_acceptance!

    render json: @call.push_event_data
  end

  private

  def record_join_intent!
    @call.with_lock do
      raise_if_claimed_by_other_agent!

      Wavoip::Calls::JoiningAgentCache.write_if_unset(@call.id, Current.user.id)
    end
  end

  def record_agent_acceptance!
    @call.with_lock do
      raise_if_claimed_by_other_agent!
      return if @call.accepted_by_agent_id == Current.user.id

      accept_call_for_current_user!
    end
  end

  def raise_if_claimed_by_other_agent!
    return unless claimed_by_other_agent?

    agent = @call.accepted_by_agent
    raise CustomExceptions::CallAlreadyAccepted.new(
      agent_name: agent&.available_name || agent&.name
    )
  end

  def claimed_by_other_agent?
    @call.accepted_by_agent_id.present? && @call.accepted_by_agent_id != Current.user.id
  end

  def accept_call_for_current_user!
    @call.update!(accepted_by_agent_id: Current.user.id)
    Wavoip::Calls::JoiningAgentCache.delete(@call.id)
    Voice::CallMessageBuilder.new(@call).update_status!(
      status: @call.status,
      agent: Current.user,
      duration_seconds: @call.duration_seconds
    )
    Wavoip::Calls::Broadcaster.new(inbox: @call.inbox).broadcast_agent_accepted(
      @call.reload,
      accepted_by_agent_id: Current.user.id
    )
    Wavoip::Calls::AssigneeOnAcceptService.new(
      call: @call,
      agent: Current.user
    ).perform!
  end

  def render_call_already_accepted(error)
    render json: { error: error.message }, status: :conflict
  end

  def fetch_call
    @call = Current.account.calls.find(params[:id])
  end
end
