# frozen_string_literal: true

class Api::V1::Accounts::CallsController < Api::V1::Accounts::BaseController
  before_action :fetch_call

  def update
    authorize @call.inbox, :show?

    return render json: { error: 'Call provider not supported' }, status: :unprocessable_entity unless @call.wavoip?

    return render json: { error: 'Call is not active' }, status: :unprocessable_entity unless @call.ringing? || @call.in_progress?

    record_agent_acceptance!

    render json: @call.push_event_data
  end

  private

  def record_agent_acceptance!
    @call.with_lock do
      next if @call.accepted_by_agent_id.present?

      @call.update!(accepted_by_agent_id: Current.user.id)
      Voice::CallMessageBuilder.new(@call).update_status!(
        status: @call.status,
        agent: Current.user,
        duration_seconds: @call.duration_seconds
      )
      Wavoip::Calls::Broadcaster.new(inbox: @call.inbox).broadcast_agent_accepted(
        @call.reload,
        accepted_by_agent_id: Current.user.id
      )
    end
  end

  def fetch_call
    @call = Current.account.calls.find(params[:id])
  end
end
