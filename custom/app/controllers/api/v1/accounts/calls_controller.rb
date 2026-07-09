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
      ensure_join_claim!
    end
  end

  def record_agent_acceptance!
    deferred = []
    @call.with_lock do
      raise_if_claimed_by_other_agent!
      next if @call.accepted_by_agent_id == Current.user.id

      ensure_join_claim!
      accept_call_for_current_user!(deferred: deferred)
    end
    run_deferred!(deferred)
  end

  # Atomically claim the join slot (or keep it if this agent already holds it).
  # Raises CallAlreadyAccepted when another agent owns accepted_by or the cache.
  def ensure_join_claim!
    return if Wavoip::Calls::JoiningAgentCache.write_if_unset(@call.id, Current.user.id)
    return if Wavoip::Calls::JoiningAgentCache.read(@call.id) == Current.user.id

    raise_already_accepted!(joining_agent_from_cache)
  end

  def raise_if_claimed_by_other_agent!
    return unless claimed_by_other_agent?

    raise_already_accepted!(@call.accepted_by_agent)
  end

  def claimed_by_other_agent?
    @call.accepted_by_agent_id.present? && @call.accepted_by_agent_id != Current.user.id
  end

  def joining_agent_from_cache
    User.find_by(id: Wavoip::Calls::JoiningAgentCache.read(@call.id))
  end

  def raise_already_accepted!(agent)
    raise CustomExceptions::CallAlreadyAccepted.new(
      agent_name: agent&.available_name || agent&.name
    )
  end

  def accept_call_for_current_user!(deferred:)
    @call.update!(accepted_by_agent_id: Current.user.id)
    Wavoip::Calls::JoiningAgentCache.delete(@call.id)
    Wavoip::Calls::CallFinalizer.sync_message_and_conversation!(@call, agent: Current.user)
    deferred << lambda {
      Wavoip::Calls::Broadcaster.new(inbox: @call.inbox).broadcast_agent_accepted(
        @call.reload,
        accepted_by_agent_id: Current.user.id
      )
    }
    Wavoip::Calls::AssigneeOnAcceptService.new(
      call: @call,
      agent: Current.user
    ).perform!
  end

  def run_deferred!(deferred)
    deferred.each(&:call)
  end

  def render_call_already_accepted(error)
    render json: { error: error.message }, status: :conflict
  end

  def fetch_call
    @call = Current.account.calls.find(params[:id])
  end
end
