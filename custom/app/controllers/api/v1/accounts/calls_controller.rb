# frozen_string_literal: true

class Api::V1::Accounts::CallsController < Api::V1::Accounts::BaseController
  before_action :fetch_call

  def update
    authorize @call.inbox, :show?

    return render json: { error: 'Call provider not supported' }, status: :unprocessable_entity unless @call.wavoip?

    return render json: { error: 'Call is not active' }, status: :unprocessable_entity unless @call.ringing? || @call.in_progress?

    @call.with_lock do
      @call.reload
      if @call.accepted_by_agent_id.blank?
        @call.update!(accepted_by_agent_id: Current.user.id)
        Voice::CallMessageBuilder.new(@call).update_status!(
          status: @call.status,
          agent: Current.user,
          duration_seconds: @call.duration_seconds
        )
      end
    end

    render json: @call.push_event_data
  end

  private

  def fetch_call
    @call = Current.account.calls.find(params[:id])
  end
end
